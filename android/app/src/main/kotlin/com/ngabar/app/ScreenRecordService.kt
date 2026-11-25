package com.ngabar.app

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Surface
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.min

class ScreenRecordService : Service() {

    companion object {
        const val ACTION_START = "com.ngabar.app.SCREEN_RECORD_START"
        const val ACTION_STOP = "com.ngabar.app.SCREEN_RECORD_STOP"

        const val EXTRA_OUTPUT_PATH = "output_path"
        const val EXTRA_WIDTH = "width"
        const val EXTRA_HEIGHT = "height"
        const val EXTRA_DPI = "dpi"
        const val EXTRA_CAPTURE_MIC = "capture_mic"
        const val EXTRA_IN_MAGLIS = "in_maglis"
        const val EXTRA_EXTERNAL_MIC_ACTIVE = "external_mic_active"

        private const val CHANNEL_ID = "ngabar_screen_record_channel"
        private const val NOTIFICATION_ID = 3001

        private const val AUDIO_SAMPLE_RATE = 44100
        private const val AUDIO_CHANNEL_COUNT = 1
        private const val AUDIO_BIT_RATE = 96_000
        private const val AUDIO_SAMPLES_PER_FRAME = 1024
        private const val RING_CAPACITY = AUDIO_SAMPLE_RATE * 3 // ~3 seconds buffer

        @Volatile
        var pendingResultCode: Int = Activity.RESULT_CANCELED

        @Volatile
        var pendingResultData: Intent? = null

        @Volatile
        private var activeInstance: ScreenRecordService? = null

        @Volatile
        var isCurrentlyRecording: Boolean = false
            private set

        @Volatile
        var onStateChanged: ((isRecording: Boolean, filePath: String?, durationMs: Long, error: String?) -> Unit)? = null

        fun appendExternalMicPcm16(pcm16LeBytes: ByteArray) {
            activeInstance?.enqueueExternalMicBytes(pcm16LeBytes)
        }

        fun updateAudioContext(externalMicActive: Boolean, inMaglis: Boolean) {
            activeInstance?.setAudioContextInternal(externalMicActive, inMaglis)
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val stopping = AtomicBoolean(false)

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var inputSurface: Surface? = null

    private var videoCodec: MediaCodec? = null
    private var audioCodec: MediaCodec? = null
    private var muxer: MediaMuxer? = null

    private var outputPath: String = ""
    private var startMonoUs: Long = 0L
    private var startWallMs: Long = 0L

    private val muxerLock = Any()
    private var videoTrackIndex = -1
    private var audioTrackIndex = -1
    private var muxerStarted = false
    private var videoFormatReady = false
    private var audioFormatReady = false
    private var audioEnabled = true
    private var lastVideoPtsUs = -1L
    private var lastAudioPtsUs = -1L

    private var videoDrainThread: Thread? = null
    private var audioLoopThread: Thread? = null
    private var playbackReaderThread: Thread? = null
    private var fallbackMicThread: Thread? = null

    private var playbackRecord: AudioRecord? = null
    private var fallbackMicRecord: AudioRecord? = null
    private val fallbackMicControlLock = Any()

    @Volatile
    private var captureMicIfIdle = true

    @Volatile
    private var inMaglis = false

    @Volatile
    private var externalMicActive = false

    // Circular PCM buffers at 44100 Hz mono
    private val externalMicRing = PcmRingBuffer(RING_CAPACITY)
    private val playbackRing = PcmRingBuffer(RING_CAPACITY)
    private val fallbackMicRing = PcmRingBuffer(RING_CAPACITY)

    // Resampler state for 16000 Hz -> 44100 Hz linear interpolation
    private val resampleLock = Any()
    private var lastMicSample: Short = 0
    private var resamplePhase: Double = 0.0

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            stopRecordingInternal(error = null)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopRecordingInternal(error = null)
                return START_NOT_STICKY
            }

            ACTION_START -> {
                if (isCurrentlyRecording) {
                    return START_NOT_STICKY
                }
                val resCode = pendingResultCode
                val resData = pendingResultData
                pendingResultCode = Activity.RESULT_CANCELED
                pendingResultData = null

                if (resCode != Activity.RESULT_OK || resData == null) {
                    notifyState(false, null, 0L, "Screen capture permission denied")
                    stopSelf()
                    return START_NOT_STICKY
                }

                outputPath = intent.getStringExtra(EXTRA_OUTPUT_PATH) ?: ""
                val width = intent.getIntExtra(EXTRA_WIDTH, 720)
                val height = intent.getIntExtra(EXTRA_HEIGHT, 1280)
                val dpi = intent.getIntExtra(EXTRA_DPI, 320)
                captureMicIfIdle = intent.getBooleanExtra(EXTRA_CAPTURE_MIC, true)
                inMaglis = intent.getBooleanExtra(EXTRA_IN_MAGLIS, false)
                externalMicActive = intent.getBooleanExtra(EXTRA_EXTERNAL_MIC_ACTIVE, false)

                if (outputPath.isEmpty()) {
                    notifyState(false, null, 0L, "Invalid output file path")
                    stopSelf()
                    return START_NOT_STICKY
                }

                startForegroundWithNotification()
                startRecordingInternal(resCode, resData, width, height, dpi)
            }
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        stopRecordingInternal(error = null)
    }

    override fun onDestroy() {
        stopRecordingInternal(error = null)
        super.onDestroy()
    }

    private fun startForegroundWithNotification() {
        createNotificationChannel()
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPending = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val stopIntent = Intent(this, ScreenRecordService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val largeIcon = try {
            BitmapFactory.decodeResource(resources, R.mipmap.ic_launcher)
        } catch (_: Exception) {
            null
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(0xFFE11D48.toInt())
            .setContentTitle("ngabar — Merekam Layar")
            .setContentText("Ketuk untuk membuka aplikasi atau Hentikan rekaman")
            .setContentIntent(openPending)
            .addAction(0, "Stop", stopPending)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)

        if (largeIcon != null) {
            builder.setLargeIcon(largeIcon)
        }

        val notification: Notification = builder.build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun startRecordingInternal(
        resultCode: Int,
        resultData: Intent,
        rawWidth: Int,
        rawHeight: Int,
        dpi: Int
    ) {
        stopping.set(false)
        activeInstance = this

        try {
            val outFile = File(outputPath)
            outFile.parentFile?.mkdirs()
            if (outFile.exists()) outFile.delete()

            val projectionManager =
                getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val projection = projectionManager.getMediaProjection(resultCode, resultData)
            if (projection == null) {
                throw IllegalStateException("MediaProjection returned null")
            }
            mediaProjection = projection
            projection.registerCallback(projectionCallback, mainHandler)

            // Ensure width & height are multiples of 16 for broad hardware AVC encoder compatibility
            val width = max(320, (rawWidth / 16) * 16)
            val height = max(320, (rawHeight / 16) * 16)

            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            synchronized(muxerLock) {
                videoTrackIndex = -1
                audioTrackIndex = -1
                muxerStarted = false
                videoFormatReady = false
                audioFormatReady = false
                lastVideoPtsUs = -1L
                lastAudioPtsUs = -1L
            }

            // 1. Setup Audio Encoder (AAC-LC 44.1kHz Mono)
            audioEnabled = setupAudioEncoder()

            // 2. Setup Video Encoder (H.264 AVC)
            val videoFormat = MediaFormat.createVideoFormat(
                MediaFormat.MIMETYPE_VIDEO_AVC,
                width,
                height
            ).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
                )
                setInteger(MediaFormat.KEY_BIT_RATE, 3_000_000)
                setInteger(MediaFormat.KEY_FRAME_RATE, 30)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
            }

            val vCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            vCodec.configure(videoFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            inputSurface = vCodec.createInputSurface()
            vCodec.start()
            videoCodec = vCodec

            startMonoUs = System.nanoTime() / 1000L
            startWallMs = System.currentTimeMillis()
            isCurrentlyRecording = true

            // 3. Start Audio capture & mixer BEFORE VirtualDisplay so audio format is ready early
            if (audioEnabled) {
                startAudioCaptureAndMixer(projection)
            }

            // 4. Start Video drain loop
            videoDrainThread = Thread({ drainVideoLoop() }, "NgabarVideoDrain").apply {
                start()
            }

            // 5. Create VirtualDisplay
            virtualDisplay = projection.createVirtualDisplay(
                "NgabarScreenRecord",
                width,
                height,
                dpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                inputSurface,
                null,
                null
            )

            notifyState(true, outputPath, 0L, null)
        } catch (e: Throwable) {
            stopRecordingInternal(error = e.message ?: "Screen recording failed to start")
        }
    }

    private fun setupAudioEncoder(): Boolean {
        return try {
            val format = MediaFormat.createAudioFormat(
                MediaFormat.MIMETYPE_AUDIO_AAC,
                AUDIO_SAMPLE_RATE,
                AUDIO_CHANNEL_COUNT
            ).apply {
                setInteger(
                    MediaFormat.KEY_AAC_PROFILE,
                    MediaCodecInfo.CodecProfileLevel.AACObjectLC
                )
                setInteger(MediaFormat.KEY_BIT_RATE, AUDIO_BIT_RATE)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
            }
            val aCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            aCodec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            aCodec.start()
            audioCodec = aCodec
            true
        } catch (_: Throwable) {
            audioCodec = null
            false
        }
    }

    private fun startAudioCaptureAndMixer(projection: MediaProjection) {
        // Internal Playback Capture (API 29+) — captures Majlis WebRTC audio + Murottal without touching MIC!
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val config = AudioPlaybackCaptureConfiguration.Builder(projection)
                    .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                    .addMatchingUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .addMatchingUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING)
                    .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                    .build()

                val minBuf = AudioRecord.getMinBufferSize(
                    AUDIO_SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT
                ).coerceAtLeast(AUDIO_SAMPLES_PER_FRAME * 4)

                val rec = AudioRecord.Builder()
                    .setAudioPlaybackCaptureConfig(config)
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(AUDIO_SAMPLE_RATE)
                            .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                            .build()
                    )
                    .setBufferSizeInBytes(minBuf * 2)
                    .build()

                if (rec.state == AudioRecord.STATE_INITIALIZED) {
                    rec.startRecording()
                    playbackRecord = rec
                    playbackReaderThread = Thread({
                        val temp = ShortArray(AUDIO_SAMPLES_PER_FRAME)
                        while (!stopping.get() && isCurrentlyRecording) {
                            val read = try {
                                rec.read(temp, 0, temp.size)
                            } catch (_: Throwable) {
                                -1
                            }
                            if (read > 0) {
                                playbackRing.write(temp, read)
                            } else if (read < 0) {
                                break
                            }
                        }
                    }, "NgabarPlaybackCapture").apply { start() }
                } else {
                    rec.release()
                }
            } catch (_: Throwable) {
                playbackRecord = null
            }
        }

        // Start optional fallback mic only if solo & AI mic not currently running
        maybeStartFallbackMic()

        // Mixed AAC encoding loop synchronized to monotonic clock
        audioLoopThread = Thread({ runAudioMixerLoop() }, "NgabarAudioMixer").apply {
            start()
        }
    }

    private fun maybeStartFallbackMic() {
        synchronized(fallbackMicControlLock) {
            if (stopping.get() || !isCurrentlyRecording || !audioEnabled) return
            if (externalMicActive || inMaglis || !captureMicIfIdle) return
            if (fallbackMicRecord != null) return
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
                != PackageManager.PERMISSION_GRANTED
            ) {
                return
            }

            try {
                val minBuf = AudioRecord.getMinBufferSize(
                    AUDIO_SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT
                ).coerceAtLeast(AUDIO_SAMPLES_PER_FRAME * 4)

                val mic = AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    AUDIO_SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    minBuf * 2
                )
                if (mic.state == AudioRecord.STATE_INITIALIZED) {
                    mic.startRecording()
                    fallbackMicRecord = mic
                    fallbackMicThread = Thread({
                        val temp = ShortArray(AUDIO_SAMPLES_PER_FRAME)
                        while (!stopping.get() &&
                            isCurrentlyRecording &&
                            !externalMicActive &&
                            !inMaglis
                        ) {
                            val read = try {
                                mic.read(temp, 0, temp.size)
                            } catch (_: Throwable) {
                                -1
                            }
                            if (read > 0) {
                                fallbackMicRing.write(temp, read)
                            } else if (read < 0) {
                                break
                            }
                        }
                    }, "NgabarFallbackMic").apply { start() }
                } else {
                    mic.release()
                }
            } catch (_: Throwable) {
                fallbackMicRecord = null
            }
        }
    }

    private fun stopFallbackMicSynchronously() {
        synchronized(fallbackMicControlLock) {
            val mic = fallbackMicRecord
            fallbackMicRecord = null
            val th = fallbackMicThread
            fallbackMicThread = null
            if (mic != null) {
                try {
                    if (mic.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                        mic.stop()
                    }
                } catch (_: Throwable) {
                }
                try {
                    mic.release()
                } catch (_: Throwable) {
                }
            }
            if (th != null && th != Thread.currentThread()) {
                try {
                    th.join(150)
                } catch (_: InterruptedException) {
                }
            }
            fallbackMicRing.clear()
        }
    }

    fun setAudioContextInternal(isExternalMicActive: Boolean, isInMaglis: Boolean) {
        externalMicActive = isExternalMicActive
        inMaglis = isInMaglis
        if (isExternalMicActive || isInMaglis) {
            stopFallbackMicSynchronously()
        } else {
            externalMicRing.clear()
            synchronized(resampleLock) {
                lastMicSample = 0
                resamplePhase = 0.0
            }
            if (isCurrentlyRecording && !stopping.get()) {
                maybeStartFallbackMic()
            }
        }
    }

    fun enqueueExternalMicBytes(pcm16LeBytes: ByteArray) {
        if (!isCurrentlyRecording || stopping.get() || pcm16LeBytes.size < 2) return
        val sampleCount = pcm16LeBytes.size / 2
        val inSamples = ShortArray(sampleCount)
        ByteBuffer.wrap(pcm16LeBytes)
            .order(ByteOrder.LITTLE_ENDIAN)
            .asShortBuffer()
            .get(inSamples)

        // Resample 16000 Hz -> 44100 Hz linear interpolation
        val ratio = 16000.0 / AUDIO_SAMPLE_RATE.toDouble()
        val maxOut = ((sampleCount / ratio).toInt() + 8)
        val outSamples = ShortArray(maxOut)
        var outCount = 0

        synchronized(resampleLock) {
            var pos = resamplePhase
            while (pos < sampleCount) {
                val idx = pos.toInt()
                val frac = pos - idx
                val s0 = if (idx == 0) lastMicSample.toDouble() else inSamples[idx - 1].toDouble()
                val s1 = inSamples[idx].toDouble()
                val interp = (s0 + (s1 - s0) * frac).toInt().coerceIn(-32768, 32767)
                if (outCount < outSamples.size) {
                    outSamples[outCount++] = interp.toShort()
                }
                pos += ratio
            }
            resamplePhase = pos - sampleCount
            lastMicSample = inSamples[sampleCount - 1]
        }

        if (outCount > 0) {
            externalMicRing.write(outSamples, outCount)
        }
    }

    private fun runAudioMixerLoop() {
        val codec = audioCodec ?: return
        val bufferInfo = MediaCodec.BufferInfo()
        val playbackBuf = ShortArray(AUDIO_SAMPLES_PER_FRAME)
        val micBuf = ShortArray(AUDIO_SAMPLES_PER_FRAME)
        val fallbackBuf = ShortArray(AUDIO_SAMPLES_PER_FRAME)
        val mixedBytes = ByteArray(AUDIO_SAMPLES_PER_FRAME * 2)
        var totalSamplesQueued = 0L

        while (!stopping.get() && isCurrentlyRecording) {
            val targetElapsedUs = (System.nanoTime() / 1000L) - startMonoUs
            val queuedUs = (totalSamplesQueued * 1_000_000L) / AUDIO_SAMPLE_RATE

            // Throttle to wall-clock pace so audio stays in lockstep with video frames
            if (queuedUs > targetElapsedUs + 25_000L) {
                try {
                    Thread.sleep(10)
                } catch (_: InterruptedException) {
                }
                drainAudioOutput(codec, bufferInfo, endOfStream = false)
                continue
            }

            // Read available samples from playback & active mic source
            val pRead = playbackRing.read(playbackBuf, AUDIO_SAMPLES_PER_FRAME)
            val mRead = if (externalMicActive) {
                externalMicRing.read(micBuf, AUDIO_SAMPLES_PER_FRAME)
            } else {
                0
            }
            val fRead = if (!externalMicActive && !inMaglis) {
                fallbackMicRing.read(fallbackBuf, AUDIO_SAMPLES_PER_FRAME)
            } else {
                0
            }

            for (i in 0 until AUDIO_SAMPLES_PER_FRAME) {
                var sum = 0
                if (i < pRead) sum += playbackBuf[i].toInt()
                if (i < mRead) sum += micBuf[i].toInt()
                if (i < fRead) sum += fallbackBuf[i].toInt()
                val clamped = sum.coerceIn(-32768, 32767).toShort()
                mixedBytes[i * 2] = (clamped.toInt() and 0xFF).toByte()
                mixedBytes[i * 2 + 1] = ((clamped.toInt() ushr 8) and 0xFF).toByte()
            }

            val inputIdx = try {
                codec.dequeueInputBuffer(10_000)
            } catch (_: Throwable) {
                -1
            }

            if (inputIdx >= 0) {
                val inputBuf = codec.getInputBuffer(inputIdx)
                if (inputBuf != null) {
                    inputBuf.clear()
                    inputBuf.put(mixedBytes)
                    val ptsUs = (totalSamplesQueued * 1_000_000L) / AUDIO_SAMPLE_RATE
                    codec.queueInputBuffer(inputIdx, 0, mixedBytes.size, ptsUs, 0)
                    totalSamplesQueued += AUDIO_SAMPLES_PER_FRAME
                }
            }

            drainAudioOutput(codec, bufferInfo, endOfStream = false)
        }

        // Send audio EOS cleanly
        try {
            val inputIdx = codec.dequeueInputBuffer(50_000)
            if (inputIdx >= 0) {
                val ptsUs = (totalSamplesQueued * 1_000_000L) / AUDIO_SAMPLE_RATE
                codec.queueInputBuffer(
                    inputIdx,
                    0,
                    0,
                    ptsUs,
                    MediaCodec.BUFFER_FLAG_END_OF_STREAM
                )
            }
            drainAudioOutput(codec, bufferInfo, endOfStream = true)
        } catch (_: Throwable) {
        }
    }

    private fun drainAudioOutput(
        codec: MediaCodec,
        bufferInfo: MediaCodec.BufferInfo,
        endOfStream: Boolean
    ) {
        val timeoutUs = if (endOfStream) 20_000L else 0L
        var loops = 0
        while (loops < 64) {
            loops++
            val outIdx = try {
                codec.dequeueOutputBuffer(bufferInfo, timeoutUs)
            } catch (_: Throwable) {
                break
            }
            if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER) {
                if (!endOfStream) break
            } else if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                synchronized(muxerLock) {
                    if (!audioFormatReady && muxer != null) {
                        audioTrackIndex = muxer!!.addTrack(codec.outputFormat)
                        audioFormatReady = true
                        maybeStartMuxerLocked()
                    }
                }
            } else if (outIdx >= 0) {
                val outBuf = codec.getOutputBuffer(outIdx)
                if (outBuf != null &&
                    bufferInfo.size > 0 &&
                    (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0
                ) {
                    synchronized(muxerLock) {
                        if (muxerStarted && audioTrackIndex >= 0 && muxer != null) {
                            val pts = max(lastAudioPtsUs + 1L, bufferInfo.presentationTimeUs)
                            bufferInfo.presentationTimeUs = pts
                            lastAudioPtsUs = pts
                            outBuf.position(bufferInfo.offset)
                            outBuf.limit(bufferInfo.offset + bufferInfo.size)
                            muxer!!.writeSampleData(audioTrackIndex, outBuf, bufferInfo)
                        }
                    }
                }
                codec.releaseOutputBuffer(outIdx, false)
                if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    break
                }
            }
        }
    }

    private fun drainVideoLoop() {
        val codec = videoCodec ?: return
        val bufferInfo = MediaCodec.BufferInfo()
        var stopWaitTicks = 0

        while (true) {
            val outIdx = try {
                codec.dequeueOutputBuffer(bufferInfo, 25_000L)
            } catch (_: Throwable) {
                break
            }

            if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER) {
                if (stopping.get()) {
                    stopWaitTicks++
                    if (stopWaitTicks > 60) {
                        break
                    }
                    continue
                }
            } else {
                stopWaitTicks = 0
            }

            if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                synchronized(muxerLock) {
                    if (!videoFormatReady && muxer != null) {
                        videoTrackIndex = muxer!!.addTrack(codec.outputFormat)
                        videoFormatReady = true
                        maybeStartMuxerLocked()
                    }
                }
            } else if (outIdx >= 0) {
                val outBuf = codec.getOutputBuffer(outIdx)
                if (outBuf != null &&
                    bufferInfo.size > 0 &&
                    (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0
                ) {
                    synchronized(muxerLock) {
                        if (muxerStarted && videoTrackIndex >= 0 && muxer != null) {
                            val relPts = max(0L, bufferInfo.presentationTimeUs - startMonoUs)
                            val pts = max(lastVideoPtsUs + 1L, relPts)
                            bufferInfo.presentationTimeUs = pts
                            lastVideoPtsUs = pts
                            outBuf.position(bufferInfo.offset)
                            outBuf.limit(bufferInfo.offset + bufferInfo.size)
                            muxer!!.writeSampleData(videoTrackIndex, outBuf, bufferInfo)
                        }
                    }
                }
                codec.releaseOutputBuffer(outIdx, false)
                if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    break
                }
            }
        }
    }

    private fun maybeStartMuxerLocked() {
        if (muxerStarted) return
        val ready = videoFormatReady && (!audioEnabled || audioFormatReady)
        if (ready && muxer != null) {
            muxer!!.start()
            muxerStarted = true
            // Request an immediate keyframe so frame 0 in the MP4 is clean & playable
            try {
                val params = Bundle().apply {
                    putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0)
                }
                videoCodec?.setParameters(params)
            } catch (_: Throwable) {
            }
        }
    }

    private fun stopRecordingInternal(error: String?) {
        if (!stopping.compareAndSet(false, true)) return

        val wasRecording = isCurrentlyRecording
        isCurrentlyRecording = false
        val savedPath = outputPath
        val durationMs = if (startWallMs > 0L) {
            max(0L, System.currentTimeMillis() - startWallMs)
        } else {
            0L
        }

        // Run teardown on background thread to avoid blocking Main/UI thread while flushing codecs
        Thread({
            stopFallbackMicSynchronously()

            try {
                playbackRecord?.let {
                    if (it.recordingState == AudioRecord.RECORDSTATE_RECORDING) it.stop()
                    it.release()
                }
            } catch (_: Throwable) {
            }
            playbackRecord = null

            try {
                playbackReaderThread?.join(250)
            } catch (_: InterruptedException) {
            }
            playbackReaderThread = null

            try {
                audioLoopThread?.join(800)
            } catch (_: InterruptedException) {
            }
            audioLoopThread = null

            try {
                videoCodec?.signalEndOfInputStream()
            } catch (_: Throwable) {
            }

            try {
                videoDrainThread?.join(1500)
            } catch (_: InterruptedException) {
            }
            videoDrainThread = null

            try {
                virtualDisplay?.release()
            } catch (_: Throwable) {
            }
            virtualDisplay = null

            try {
                inputSurface?.release()
            } catch (_: Throwable) {
            }
            inputSurface = null

            try {
                videoCodec?.stop()
                videoCodec?.release()
            } catch (_: Throwable) {
            }
            videoCodec = null

            try {
                audioCodec?.stop()
                audioCodec?.release()
            } catch (_: Throwable) {
            }
            audioCodec = null

            var finalizedValid = false
            synchronized(muxerLock) {
                if (muxer != null) {
                    if (muxerStarted) {
                        try {
                            muxer!!.stop()
                            finalizedValid = true
                        } catch (_: Throwable) {
                            finalizedValid = false
                        }
                    }
                    try {
                        muxer!!.release()
                    } catch (_: Throwable) {
                    }
                    muxer = null
                }
                muxerStarted = false
            }

            try {
                mediaProjection?.unregisterCallback(projectionCallback)
                mediaProjection?.stop()
            } catch (_: Throwable) {
            }
            mediaProjection = null

            activeInstance = null
            externalMicRing.clear()
            playbackRing.clear()

            if (!finalizedValid || error != null) {
                try {
                    if (savedPath.isNotEmpty()) File(savedPath).delete()
                } catch (_: Throwable) {
                }
            }

            if (wasRecording || error != null) {
                notifyState(
                    false,
                    if (finalizedValid && error == null) savedPath else null,
                    durationMs,
                    error
                )
            }

            mainHandler.post {
                stopForegroundSafely()
            }
        }, "NgabarScreenRecStop").start()
    }

    private fun notifyState(
        recording: Boolean,
        filePath: String?,
        durationMs: Long,
        error: String?
    ) {
        mainHandler.post {
            onStateChanged?.invoke(recording, filePath, durationMs, error)
        }
    }

    private fun stopForegroundSafely() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
        } catch (_: Throwable) {
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Screen Recording",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Notification shown while recording screen in Ngabar"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    private class PcmRingBuffer(private val capacity: Int) {
        private val buffer = ShortArray(capacity)
        private var readPos = 0
        private var writePos = 0
        private var count = 0

        @Synchronized
        fun write(data: ShortArray, len: Int) {
            val toWrite = min(len, data.size)
            for (i in 0 until toWrite) {
                if (count == capacity) {
                    readPos = (readPos + 1) % capacity
                    count--
                }
                buffer[writePos] = data[i]
                writePos = (writePos + 1) % capacity
                count++
            }
        }

        @Synchronized
        fun read(dest: ShortArray, requested: Int): Int {
            val n = min(requested, count)
            for (i in 0 until n) {
                dest[i] = buffer[readPos]
                readPos = (readPos + 1) % capacity
                count--
            }
            return n
        }

        @Synchronized
        fun clear() {
            readPos = 0
            writePos = 0
            count = 0
        }
    }
}
