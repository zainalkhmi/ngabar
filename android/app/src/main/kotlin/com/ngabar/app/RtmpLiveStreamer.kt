package com.ngabar.app

import android.media.MediaCodec
import android.media.MediaFormat
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.EOFException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URI
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.SecureRandom
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
import kotlin.math.max
import kotlin.math.min

/**
 * Lightweight, dependency-free pure Kotlin RTMP / RTMPS (TLS) live streamer.
 *
 * Designed specifically for AI safety alongside Sherpa-ONNX:
 * - Uses a bounded non-blocking packet queue so slow mobile/Wi-Fi networks drop
 *   excess non-keyframe video frames instead of stalling MediaCodec, AudioMixer,
 *   or the AI speech recognition isolate.
 * - Supports both `rtmp://` (YouTube) and `rtmps://` (Facebook Live & YouTube RTMPS).
 */
class RtmpLiveStreamer(
    private val fullUrl: String,
    private val onState: (status: String, error: String?) -> Unit,
    private val onStats: (bitrateKbps: Int, droppedFrames: Int) -> Unit
) {
    private data class RtmpPacket(
        val csid: Int,
        val timestampMs: Long,
        val msgTypeId: Int,
        val msgStreamId: Int,
        val payload: ByteArray,
        val isVideo: Boolean = false,
        val isKeyframe: Boolean = false,
        val isHeader: Boolean = false
    )

    private class ChunkReadState {
        var timestamp: Long = 0L
        var timestampDelta: Long = 0L
        var msgLength: Int = 0
        var msgTypeId: Int = 0
        var msgStreamId: Int = 0
        var buffer: ByteArrayOutputStream? = null
        var remaining: Int = 0
    }

    companion object {
        private const val RTMP_VERSION: Byte = 3
        private const val HANDSHAKE_SIZE = 1536
        private const val DEFAULT_CHUNK_SIZE = 128
        private const val OUT_CHUNK_SIZE = 4096

        private const val MSG_SET_CHUNK_SIZE = 1
        private const val MSG_ABORT = 2
        private const val MSG_ACK = 3
        private const val MSG_USER_CONTROL = 4
        private const val MSG_WINDOW_ACK_SIZE = 5
        private const val MSG_SET_PEER_BANDWIDTH = 6
        private const val MSG_AUDIO = 8
        private const val MSG_VIDEO = 9
        private const val MSG_AMF0_DATA = 18
        private const val MSG_AMF0_COMMAND = 20

        private const val CSID_CONTROL = 2
        private const val CSID_COMMAND = 3
        private const val CSID_AUDIO = 4
        private const val CSID_VIDEO = 5
        private const val CSID_DATA = 6

        private const val MAX_QUEUE_CAPACITY = 96
        private const val DROP_NON_KEY_THRESHOLD = 64
    }

    private val running = AtomicBoolean(false)
    private val connected = AtomicBoolean(false)
    private val packetQueue = ArrayBlockingQueue<RtmpPacket>(MAX_QUEUE_CAPACITY)

    private var socket: Socket? = null
    private var input: BufferedInputStream? = null
    private var output: BufferedOutputStream? = null
    private var writerThread: Thread? = null
    private var readerThread: Thread? = null

    private var streamId: Int = 1
    private var inChunkSize: Int = DEFAULT_CHUNK_SIZE
    private val bytesSentWindow = AtomicLong(0L)
    private val droppedVideoFrames = AtomicLong(0L)
    private val lastStatsWallMs = AtomicLong(0L)
    private val bytesSentSinceStats = AtomicLong(0L)

    @Volatile
    private var videoHeaderSent = false

    @Volatile
    private var audioHeaderSent = false

    @Volatile
    private var lastSps: ByteArray? = null

    @Volatile
    private var lastPps: ByteArray? = null

    @Volatile
    private var publishStarted = false

    @Volatile
    private var pendingCommandTxId = -1
    private val commandResponses = HashMap<Int, List<Any?>>()
    private val commandLock = Object()

    fun startAsync() {
        if (!running.compareAndSet(false, true)) return
        onState("connecting", null)
        writerThread = Thread({ runStreamerLoop() }, "NgabarRtmpWriter").apply {
            start()
        }
    }

    fun stop() {
        if (!running.compareAndSet(true, false)) {
            closeSocketQuietly()
            return
        }
        connected.set(false)
        packetQueue.clear()
        // Wake writer if waiting
        packetQueue.offer(RtmpPacket(0, 0, 0, 0, ByteArray(0)))
        closeSocketQuietly()
        try {
            writerThread?.join(800)
        } catch (_: InterruptedException) {
        }
        writerThread = null
        try {
            readerThread?.join(400)
        } catch (_: InterruptedException) {
        }
        readerThread = null
    }

    fun onVideoFormatChanged(format: MediaFormat) {
        val nals = ArrayList<ByteArray>()
        format.getByteBuffer("csd-0")?.let { extractAnnexBNals(it, nals) }
        format.getByteBuffer("csd-1")?.let { extractAnnexBNals(it, nals) }
        processConfigNals(nals)
    }

    fun onAudioFormatChanged(format: MediaFormat) {
        val csd0 = format.getByteBuffer("csd-0") ?: return
        val dup = csd0.duplicate()
        val asc = ByteArray(dup.remaining())
        dup.get(asc)
        if (asc.isEmpty()) return

        val tag = ByteArray(2 + asc.size)
        tag[0] = 0xAF.toByte() // AAC, 44kHz, 16-bit, stereo flag per FLV spec
        tag[1] = 0x00          // AAC sequence header
        System.arraycopy(asc, 0, tag, 2, asc.size)

        audioHeaderSent = true
        enqueuePacket(
            RtmpPacket(
                csid = CSID_AUDIO,
                timestampMs = 0L,
                msgTypeId = MSG_AUDIO,
                msgStreamId = streamId,
                payload = tag,
                isVideo = false,
                isKeyframe = false,
                isHeader = true
            )
        )
    }

    fun sendVideoFrame(buffer: ByteBuffer, info: MediaCodec.BufferInfo, ptsUs: Long) {
        if (!running.get() || !connected.get()) return
        val dup = buffer.duplicate()
        dup.position(info.offset)
        dup.limit(info.offset + info.size)

        val nals = ArrayList<ByteArray>()
        extractAnnexBNals(dup, nals)
        if (nals.isEmpty()) return

        if ((info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
            processConfigNals(nals)
            return
        }

        // Check if inline SPS/PPS arrived inside a keyframe buffer
        val configNals = ArrayList<ByteArray>()
        val vclNals = ArrayList<ByteArray>()
        var isIdr = (info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0

        for (nal in nals) {
            if (nal.isEmpty()) continue
            val nalType = nal[0].toInt() and 0x1F
            if (nalType == 7 || nalType == 8) {
                configNals.add(nal)
            } else {
                if (nalType == 5) isIdr = true
                vclNals.add(nal)
            }
        }

        if (configNals.isNotEmpty() && !videoHeaderSent) {
            processConfigNals(configNals)
        }
        if (vclNals.isEmpty() || !videoHeaderSent) return

        var totalAvccBytes = 0
        for (n in vclNals) {
            totalAvccBytes += 4 + n.size
        }

        val tag = ByteArray(5 + totalAvccBytes)
        tag[0] = if (isIdr) 0x17.toByte() else 0x27.toByte()
        tag[1] = 0x01 // AVC NALU
        tag[2] = 0x00 // CTS = 0 (Baseline profile: no B-frames)
        tag[3] = 0x00
        tag[4] = 0x00

        var pos = 5
        for (n in vclNals) {
            val len = n.size
            tag[pos++] = ((len ushr 24) and 0xFF).toByte()
            tag[pos++] = ((len ushr 16) and 0xFF).toByte()
            tag[pos++] = ((len ushr 8) and 0xFF).toByte()
            tag[pos++] = (len and 0xFF).toByte()
            System.arraycopy(n, 0, tag, pos, len)
            pos += len
        }

        val tsMs = max(0L, ptsUs / 1000L)
        enqueuePacket(
            RtmpPacket(
                csid = CSID_VIDEO,
                timestampMs = tsMs,
                msgTypeId = MSG_VIDEO,
                msgStreamId = streamId,
                payload = tag,
                isVideo = true,
                isKeyframe = isIdr,
                isHeader = false
            )
        )
    }

    fun sendAudioFrame(buffer: ByteBuffer, info: MediaCodec.BufferInfo, ptsUs: Long) {
        if (!running.get() || !connected.get() || !audioHeaderSent) return
        if ((info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) return
        if (info.size <= 0) return

        val dup = buffer.duplicate()
        dup.position(info.offset)
        dup.limit(info.offset + info.size)

        val raw = ByteArray(info.size)
        dup.get(raw)

        val tag = ByteArray(2 + raw.size)
        tag[0] = 0xAF.toByte()
        tag[1] = 0x01 // AAC raw frame
        System.arraycopy(raw, 0, tag, 2, raw.size)

        val tsMs = max(0L, ptsUs / 1000L)
        enqueuePacket(
            RtmpPacket(
                csid = CSID_AUDIO,
                timestampMs = tsMs,
                msgTypeId = MSG_AUDIO,
                msgStreamId = streamId,
                payload = tag,
                isVideo = false,
                isKeyframe = false,
                isHeader = false
            )
        )
    }

    private fun processConfigNals(nals: List<ByteArray>) {
        for (nal in nals) {
            if (nal.isEmpty()) continue
            val nalType = nal[0].toInt() and 0x1F
            if (nalType == 7) {
                lastSps = nal
            } else if (nalType == 8) {
                lastPps = nal
            }
        }
        val sps = lastSps ?: return
        val pps = lastPps ?: return
        if (sps.size < 4) return

        // Build AVCDecoderConfigurationRecord
        val avcc = ByteArrayOutputStream(16 + sps.size + pps.size)
        avcc.write(0x01)               // configurationVersion
        avcc.write(sps[1].toInt())     // AVCProfileIndication
        avcc.write(sps[2].toInt())     // profile_compatibility
        avcc.write(sps[3].toInt())     // AVCLevelIndication
        avcc.write(0xFF)               // lengthSizeMinusOne = 3 (4 bytes)
        avcc.write(0xE1)               // numOfSequenceParameterSets = 1
        avcc.write((sps.size ushr 8) and 0xFF)
        avcc.write(sps.size and 0xFF)
        avcc.write(sps)
        avcc.write(0x01)               // numOfPictureParameterSets = 1
        avcc.write((pps.size ushr 8) and 0xFF)
        avcc.write(pps.size and 0xFF)
        avcc.write(pps)

        val avccBytes = avcc.toByteArray()
        val tag = ByteArray(5 + avccBytes.size)
        tag[0] = 0x17.toByte() // keyframe + AVC
        tag[1] = 0x00          // AVC sequence header
        tag[2] = 0x00
        tag[3] = 0x00
        tag[4] = 0x00
        System.arraycopy(avccBytes, 0, tag, 5, avccBytes.size)

        videoHeaderSent = true
        enqueuePacket(
            RtmpPacket(
                csid = CSID_VIDEO,
                timestampMs = 0L,
                msgTypeId = MSG_VIDEO,
                msgStreamId = streamId,
                payload = tag,
                isVideo = true,
                isKeyframe = true,
                isHeader = true
            )
        )
    }

    private fun enqueuePacket(pkt: RtmpPacket) {
        if (!running.get()) return

        // AI-Safe Congestion Control: if upload lags behind, drop non-keyframe video
        // frames proactively so audio & MediaCodec never stall.
        if (pkt.isVideo && !pkt.isKeyframe && !pkt.isHeader &&
            packetQueue.size >= DROP_NON_KEY_THRESHOLD
        ) {
            droppedVideoFrames.incrementAndGet()
            return
        }

        if (!packetQueue.offer(pkt)) {
            if (pkt.isVideo && !pkt.isKeyframe && !pkt.isHeader) {
                droppedVideoFrames.incrementAndGet()
                return
            }
            // Drop oldest packet to keep headers / audio flowing
            packetQueue.poll()
            packetQueue.offer(pkt)
        }
    }

    private fun runStreamerLoop() {
        try {
            val parsed = parseRtmpUrl(fullUrl)
            val sock = createConnectedSocket(parsed.scheme, parsed.host, parsed.port)
            socket = sock
            val bis = BufferedInputStream(sock.getInputStream(), 16384)
            val bos = BufferedOutputStream(sock.getOutputStream(), 32768)
            input = bis
            output = bos

            performHandshake(bis, bos)

            readerThread = Thread({ runReaderLoop(bis) }, "NgabarRtmpReader").apply {
                start()
            }

            // 1. Set outgoing chunk size to 4096
            sendSetChunkSize(bos, OUT_CHUNK_SIZE)

            // 2. Connect command
            val connectProps = linkedMapOf<String, Any?>(
                "app" to parsed.app,
                "type" to "nonprivate",
                "flashVer" to "FMLE/3.0 (compatible; ngabar)",
                "tcUrl" to parsed.tcUrl,
                "fpad" to false,
                "capabilities" to 15.0,
                "audioCodecs" to 1024.0,
                "videoCodecs" to 128.0,
                "videoFunction" to 1.0
            )
            sendAmfCommand(bos, CSID_COMMAND, 0, "connect", 1.0, connectProps)
            waitForTransactionResult(1, timeoutMs = 10_000L)

            // 3. Window Ack + Release/FCPublish + CreateStream
            sendWindowAckSize(bos, 2_500_000)
            sendAmfCommand(bos, CSID_COMMAND, 0, "releaseStream", 2.0, null, parsed.streamKey)
            sendAmfCommand(bos, CSID_COMMAND, 0, "FCPublish", 3.0, null, parsed.streamKey)
            sendAmfCommand(bos, CSID_COMMAND, 0, "createStream", 4.0, null)

            val createRes = waitForTransactionResult(4, timeoutMs = 8_000L)
            if (createRes != null && createRes.size >= 4 && createRes[3] is Number) {
                streamId = (createRes[3] as Number).toInt()
            }

            // 4. Publish
            sendAmfCommand(
                bos,
                CSID_AUDIO,
                streamId,
                "publish",
                0.0,
                null,
                parsed.streamKey,
                "live"
            )
            bos.flush()

            // Wait briefly for NetStream.Publish.Start (or proceed if server accepts stream immediately)
            val waitStart = System.currentTimeMillis()
            while (running.get() && !publishStarted && System.currentTimeMillis() - waitStart < 3500L) {
                Thread.sleep(50)
            }

            // Send FLV onMetaData so ingest servers know stream dimensions/codec
            sendOnMetaData(bos)

            connected.set(true)
            lastStatsWallMs.set(System.currentTimeMillis())
            onState("live", null)

            // Main non-blocking flush loop
            while (running.get()) {
                val pkt = packetQueue.poll(150, TimeUnit.MILLISECONDS)
                if (pkt != null) {
                    if (pkt.msgTypeId == 0 && !running.get()) break
                    writeChunkedMessage(
                        bos,
                        pkt.csid,
                        pkt.timestampMs,
                        pkt.msgTypeId,
                        pkt.msgStreamId,
                        pkt.payload
                    )
                    bytesSentSinceStats.addAndGet(pkt.payload.size.toLong())

                    // Drain any immediately queued packets before flushing socket
                    var batch = 0
                    while (batch < 16 && running.get()) {
                        val next = packetQueue.poll() ?: break
                        if (next.msgTypeId == 0 && !running.get()) break
                        writeChunkedMessage(
                            bos,
                            next.csid,
                            next.timestampMs,
                            next.msgTypeId,
                            next.msgStreamId,
                            next.payload
                        )
                        bytesSentSinceStats.addAndGet(next.payload.size.toLong())
                        batch++
                    }
                    bos.flush()
                }

                val nowMs = System.currentTimeMillis()
                val prevStatsMs = lastStatsWallMs.get()
                if (nowMs - prevStatsMs >= 1000L) {
                    if (lastStatsWallMs.compareAndSet(prevStatsMs, nowMs)) {
                        val elapsedMs = max(1L, nowMs - prevStatsMs)
                        val bytes = bytesSentSinceStats.getAndSet(0L)
                        val kbps = ((bytes * 8L) / elapsedMs).toInt()
                        onStats(kbps, droppedVideoFrames.get().toInt())
                    }
                }
            }
        } catch (t: Throwable) {
            if (running.get()) {
                onState("error", t.message ?: "RTMP connection failed")
            }
        } finally {
            connected.set(false)
            closeSocketQuietly()
        }
    }

    private data class ParsedRtmpUrl(
        val scheme: String,
        val host: String,
        val port: Int,
        val app: String,
        val streamKey: String,
        val tcUrl: String
    )

    private fun parseRtmpUrl(raw: String): ParsedRtmpUrl {
        val trimmed = raw.trim()
        val uri = URI(trimmed)
        val scheme = (uri.scheme ?: "rtmp").lowercase()
        val host = uri.host ?: throw IllegalArgumentException("Invalid RTMP host")
        val port = if (uri.port > 0) uri.port else if (scheme == "rtmps") 443 else 1935
        val path = (uri.rawPath ?: "").trim('/')
        val query = uri.rawQuery?.let { "?$it" } ?: ""
        val parts = path.split('/').filter { it.isNotEmpty() }
        if (parts.size < 2) {
            throw IllegalArgumentException("URL RTMP harus memuat nama app & Stream Key")
        }
        val app = parts[0]
        val streamKey = parts.subList(1, parts.size).joinToString("/") + query
        val defaultPort = (scheme == "rtmp" && port == 1935) || (scheme == "rtmps" && port == 443)
        val tcUrl = if (defaultPort) {
            "$scheme://$host/$app"
        } else {
            "$scheme://$host:$port/$app"
        }
        return ParsedRtmpUrl(scheme, host, port, app, streamKey, tcUrl)
    }

    private fun createConnectedSocket(scheme: String, host: String, port: Int): Socket {
        if (scheme == "rtmps") {
            val factory = SSLSocketFactory.getDefault() as SSLSocketFactory
            val ssl = factory.createSocket() as SSLSocket
            ssl.connect(InetSocketAddress(host, port), 10_000)
            ssl.soTimeout = 15_000
            ssl.tcpNoDelay = true
            ssl.startHandshake()
            return ssl
        }
        val sock = Socket()
        sock.connect(InetSocketAddress(host, port), 10_000)
        sock.soTimeout = 15_000
        sock.tcpNoDelay = true
        return sock
    }

    private fun performHandshake(bis: BufferedInputStream, bos: BufferedOutputStream) {
        val rng = SecureRandom()
        val c1 = ByteArray(HANDSHAKE_SIZE)
        rng.nextBytes(c1)
        // Timestamp (4 bytes = 0) + Zero (4 bytes = 0)
        for (i in 0 until 8) c1[i] = 0

        bos.write(RTMP_VERSION.toInt())
        bos.write(c1)
        bos.flush()

        val dis = DataInputStream(bis)
        val s0 = dis.readByte()
        if (s0 != RTMP_VERSION) {
            throw IllegalStateException("Unsupported RTMP version: $s0")
        }
        val s1 = ByteArray(HANDSHAKE_SIZE)
        dis.readFully(s1)
        val s2 = ByteArray(HANDSHAKE_SIZE)
        dis.readFully(s2)

        // Echo S1 as C2
        bos.write(s1)
        bos.flush()
    }

    private fun runReaderLoop(bis: BufferedInputStream) {
        val dis = DataInputStream(bis)
        val states = HashMap<Int, ChunkReadState>()
        try {
            while (running.get()) {
                val b0 = dis.read()
                if (b0 < 0) break
                val fmt = (b0 ushr 6) and 0x03
                var csid = b0 and 0x3F
                if (csid == 0) {
                    csid = dis.readUnsignedByte() + 64
                } else if (csid == 1) {
                    val b1 = dis.readUnsignedByte()
                    val b2 = dis.readUnsignedByte()
                    csid = (b2 shl 8) + b1 + 64
                }

                val st = states.getOrPut(csid) { ChunkReadState() }
                when (fmt) {
                    0 -> {
                        val ts = readUint24(dis).toLong()
                        st.msgLength = readUint24(dis)
                        st.msgTypeId = dis.readUnsignedByte()
                        st.msgStreamId = readInt32LE(dis)
                        st.timestamp = if (ts == 0xFFFFFFL) readUint32BE(dis) else ts
                        st.timestampDelta = 0L
                    }
                    1 -> {
                        val delta = readUint24(dis).toLong()
                        st.msgLength = readUint24(dis)
                        st.msgTypeId = dis.readUnsignedByte()
                        val actualDelta = if (delta == 0xFFFFFFL) readUint32BE(dis) else delta
                        st.timestampDelta = actualDelta
                        st.timestamp += actualDelta
                    }
                    2 -> {
                        val delta = readUint24(dis).toLong()
                        val actualDelta = if (delta == 0xFFFFFFL) readUint32BE(dis) else delta
                        st.timestampDelta = actualDelta
                        st.timestamp += actualDelta
                    }
                    3 -> {
                        // Continues previous message or repeats delta
                    }
                }

                if (st.buffer == null || st.remaining <= 0) {
                    st.buffer = ByteArrayOutputStream(max(64, st.msgLength))
                    st.remaining = st.msgLength
                }

                val toRead = min(inChunkSize, st.remaining)
                val chunkBytes = ByteArray(toRead)
                dis.readFully(chunkBytes)
                st.buffer!!.write(chunkBytes)
                st.remaining -= toRead

                if (st.remaining == 0) {
                    val fullPayload = st.buffer!!.toByteArray()
                    st.buffer = null
                    handleIncomingMessage(st.msgTypeId, fullPayload)
                }
            }
        } catch (_: EOFException) {
            if (running.get() && connected.get()) {
                onState("error", "Koneksi RTMP ditutup oleh server")
            }
        } catch (t: Throwable) {
            if (running.get() && connected.get()) {
                onState("error", t.message ?: "RTMP read error")
            }
        }
    }

    private fun handleIncomingMessage(msgTypeId: Int, payload: ByteArray) {
        when (msgTypeId) {
            MSG_SET_CHUNK_SIZE -> {
                if (payload.size >= 4) {
                    val newSize = ((payload[0].toInt() and 0x7F) shl 24) or
                        ((payload[1].toInt() and 0xFF) shl 16) or
                        ((payload[2].toInt() and 0xFF) shl 8) or
                        (payload[3].toInt() and 0xFF)
                    if (newSize > 0) inChunkSize = newSize
                }
            }
            MSG_USER_CONTROL -> {
                if (payload.size >= 6) {
                    val eventType = ((payload[0].toInt() and 0xFF) shl 8) or
                        (payload[1].toInt() and 0xFF)
                    if (eventType == 6) {
                        // PingRequest -> send PingResponse (eventType = 7)
                        val resp = payload.copyOf()
                        resp[0] = 0x00
                        resp[1] = 0x07
                        enqueuePacket(
                            RtmpPacket(
                                csid = CSID_CONTROL,
                                timestampMs = 0L,
                                msgTypeId = MSG_USER_CONTROL,
                                msgStreamId = 0,
                                payload = resp,
                                isHeader = true
                            )
                        )
                    }
                }
            }
            MSG_AMF0_COMMAND -> {
                val decoded = decodeAmf0Sequence(payload)
                if (decoded.isEmpty()) return
                val cmdName = decoded[0] as? String ?: return
                val txId = (decoded.getOrNull(1) as? Number)?.toInt() ?: 0

                if (cmdName == "_result" || cmdName == "_error") {
                    synchronized(commandLock) {
                        commandResponses[txId] = decoded
                        commandLock.notifyAll()
                    }
                    if (cmdName == "_error") {
                        val desc = extractStatusDesc(decoded) ?: "Server rejected RTMP command"
                        onState("error", desc)
                    }
                } else if (cmdName == "onStatus") {
                    val info = decoded.getOrNull(3) as? Map<*, *>
                    val code = info?.get("code")?.toString() ?: ""
                    val level = info?.get("level")?.toString() ?: ""
                    if (code == "NetStream.Publish.Start") {
                        publishStarted = true
                    } else if (level == "error") {
                        val desc = info?.get("description")?.toString() ?: code
                        onState("error", desc.ifEmpty { "Stream ditolak server" })
                    }
                }
            }
        }
    }

    private fun extractStatusDesc(decoded: List<Any?>): String? {
        for (item in decoded) {
            if (item is Map<*, *>) {
                val desc = item["description"]?.toString()
                if (!desc.isNullOrEmpty()) return desc
                val code = item["code"]?.toString()
                if (!code.isNullOrEmpty()) return code
            }
        }
        return null
    }

    private fun waitForTransactionResult(txId: Int, timeoutMs: Long): List<Any?>? {
        val deadline = System.currentTimeMillis() + timeoutMs
        synchronized(commandLock) {
            while (running.get()) {
                val resp = commandResponses.remove(txId)
                if (resp != null) return resp
                val rem = deadline - System.currentTimeMillis()
                if (rem <= 0L) return null
                commandLock.wait(min(rem, 250L))
            }
        }
        return null
    }

    private fun sendSetChunkSize(out: OutputStream, size: Int) {
        val payload = byteArrayOf(
            ((size ushr 24) and 0x7F).toByte(),
            ((size ushr 16) and 0xFF).toByte(),
            ((size ushr 8) and 0xFF).toByte(),
            (size and 0xFF).toByte()
        )
        writeChunkedMessage(out, CSID_CONTROL, 0L, MSG_SET_CHUNK_SIZE, 0, payload)
    }

    private fun sendWindowAckSize(out: OutputStream, windowSize: Int) {
        val payload = byteArrayOf(
            ((windowSize ushr 24) and 0xFF).toByte(),
            ((windowSize ushr 16) and 0xFF).toByte(),
            ((windowSize ushr 8) and 0xFF).toByte(),
            (windowSize and 0xFF).toByte()
        )
        writeChunkedMessage(out, CSID_CONTROL, 0L, MSG_WINDOW_ACK_SIZE, 0, payload)
    }

    private fun sendOnMetaData(out: OutputStream) {
        val baos = ByteArrayOutputStream(256)
        writeAmfString(baos, "@setDataFrame")
        writeAmfString(baos, "onMetaData")
        val meta = linkedMapOf<String, Any?>(
            "audiocodecid" to 10.0,
            "audiosamplerate" to 44100.0,
            "audiosamplesize" to 16.0,
            "stereo" to false,
            "videocodecid" to 7.0,
            "encoder" to "ngabar-rtmp-light"
        )
        writeAmfObject(baos, meta)
        writeChunkedMessage(out, CSID_DATA, 0L, MSG_AMF0_DATA, streamId, baos.toByteArray())
        out.flush()
    }

    private fun sendAmfCommand(
        out: OutputStream,
        csid: Int,
        msgStreamId: Int,
        name: String,
        txId: Double,
        vararg args: Any?
    ) {
        val baos = ByteArrayOutputStream(512)
        writeAmfString(baos, name)
        writeAmfNumber(baos, txId)
        for (arg in args) {
            writeAmfValue(baos, arg)
        }
        writeChunkedMessage(out, csid, 0L, MSG_AMF0_COMMAND, msgStreamId, baos.toByteArray())
        out.flush()
    }

    private fun writeChunkedMessage(
        out: OutputStream,
        csid: Int,
        timestampMs: Long,
        msgTypeId: Int,
        msgStreamId: Int,
        payload: ByteArray
    ) {
        val len = payload.size
        val hasExtTs = timestampMs >= 0xFFFFFFL
        val tsField = if (hasExtTs) 0xFFFFFFL else timestampMs

        // FMT 0 Basic Header (csid < 64)
        out.write(csid and 0x3F)
        // Timestamp (3 bytes BE)
        out.write(((tsField ushr 16) and 0xFF).toInt())
        out.write(((tsField ushr 8) and 0xFF).toInt())
        out.write((tsField and 0xFF).toInt())
        // Message Length (3 bytes BE)
        out.write((len ushr 16) and 0xFF)
        out.write((len ushr 8) and 0xFF)
        out.write(len and 0xFF)
        // Message Type ID (1 byte)
        out.write(msgTypeId and 0xFF)
        // Message Stream ID (4 bytes LE)
        out.write(msgStreamId and 0xFF)
        out.write((msgStreamId ushr 8) and 0xFF)
        out.write((msgStreamId ushr 16) and 0xFF)
        out.write((msgStreamId ushr 24) and 0xFF)

        if (hasExtTs) {
            writeUint32BE(out, timestampMs)
        }

        var offset = 0
        while (offset < len) {
            if (offset > 0) {
                // FMT 3 continuation header
                out.write((3 shl 6) or (csid and 0x3F))
                if (hasExtTs) {
                    writeUint32BE(out, timestampMs)
                }
            }
            val chunkLen = min(OUT_CHUNK_SIZE, len - offset)
            out.write(payload, offset, chunkLen)
            offset += chunkLen
        }
    }

    // ── Annex-B NALU parser ──
    private fun extractAnnexBNals(buf: ByteBuffer, out: MutableList<ByteArray>) {
        val data = ByteArray(buf.remaining())
        buf.duplicate().get(data)
        if (data.isEmpty()) return

        var i = 0
        var nalStart = -1
        while (i < data.size) {
            val scLen = startCodeLen(data, i)
            if (scLen > 0) {
                if (nalStart >= 0 && i > nalStart) {
                    out.add(data.copyOfRange(nalStart, i))
                }
                i += scLen
                nalStart = i
            } else {
                i++
            }
        }
        if (nalStart >= 0 && data.size > nalStart) {
            out.add(data.copyOfRange(nalStart, data.size))
        } else if (nalStart < 0 && data.isNotEmpty()) {
            // Raw NALU without Annex-B start code
            out.add(data)
        }
    }

    private fun startCodeLen(data: ByteArray, idx: Int): Int {
        if (idx + 3 < data.size &&
            data[idx] == 0.toByte() &&
            data[idx + 1] == 0.toByte() &&
            data[idx + 2] == 0.toByte() &&
            data[idx + 3] == 1.toByte()
        ) {
            return 4
        }
        if (idx + 2 < data.size &&
            data[idx] == 0.toByte() &&
            data[idx + 1] == 0.toByte() &&
            data[idx + 2] == 1.toByte()
        ) {
            return 3
        }
        return 0
    }

    // ── AMF0 Writer ──
    private fun writeAmfValue(out: OutputStream, value: Any?) {
        when (value) {
            null -> out.write(0x05)
            is Boolean -> {
                out.write(0x01)
                out.write(if (value) 1 else 0)
            }
            is Number -> writeAmfNumber(out, value.toDouble())
            is String -> writeAmfString(out, value)
            is Map<*, *> -> writeAmfObject(out, value)
            else -> writeAmfString(out, value.toString())
        }
    }

    private fun writeAmfNumber(out: OutputStream, v: Double) {
        out.write(0x00)
        val bits = java.lang.Double.doubleToRawLongBits(v)
        for (shift in 56 downTo 0 step 8) {
            out.write(((bits ushr shift) and 0xFFL).toInt())
        }
    }

    private fun writeAmfString(out: OutputStream, s: String) {
        val bytes = s.toByteArray(Charsets.UTF_8)
        out.write(0x02)
        out.write((bytes.size ushr 8) and 0xFF)
        out.write(bytes.size and 0xFF)
        out.write(bytes)
    }

    private fun writeAmfObject(out: OutputStream, map: Map<*, *>) {
        out.write(0x03)
        for ((k, v) in map) {
            val keyBytes = k.toString().toByteArray(Charsets.UTF_8)
            out.write((keyBytes.size ushr 8) and 0xFF)
            out.write(keyBytes.size and 0xFF)
            out.write(keyBytes)
            writeAmfValue(out, v)
        }
        out.write(0x00)
        out.write(0x00)
        out.write(0x09)
    }

    // ── AMF0 Reader ──
    private fun decodeAmf0Sequence(bytes: ByteArray): List<Any?> {
        val list = ArrayList<Any?>()
        val buf = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
        while (buf.hasRemaining()) {
            list.add(readAmf0Value(buf))
        }
        return list
    }

    private fun readAmf0Value(buf: ByteBuffer): Any? {
        if (!buf.hasRemaining()) return null
        return when (buf.get().toInt() and 0xFF) {
            0x00 -> if (buf.remaining() >= 8) buf.getDouble() else null
            0x01 -> if (buf.hasRemaining()) (buf.get().toInt() != 0) else null
            0x02 -> readAmf0ShortString(buf)
            0x03 -> readAmf0Object(buf)
            0x05, 0x06 -> null
            0x08 -> {
                // ECMA array
                if (buf.remaining() >= 4) buf.getInt()
                readAmf0Object(buf)
            }
            0x0C -> {
                if (buf.remaining() < 4) return null
                val len = buf.getInt()
                if (len <= 0 || len > buf.remaining()) return null
                val arr = ByteArray(len)
                buf.get(arr)
                String(arr, Charsets.UTF_8)
            }
            else -> null
        }
    }

    private fun readAmf0ShortString(buf: ByteBuffer): String {
        if (buf.remaining() < 2) return ""
        val len = buf.getShort().toInt() and 0xFFFF
        if (len == 0 || len > buf.remaining()) return ""
        val arr = ByteArray(len)
        buf.get(arr)
        return String(arr, Charsets.UTF_8)
    }

    private fun readAmf0Object(buf: ByteBuffer): Map<String, Any?> {
        val map = LinkedHashMap<String, Any?>()
        while (buf.remaining() >= 3) {
            val key = readAmf0ShortString(buf)
            if (key.isEmpty() && buf.hasRemaining() && (buf.get(buf.position()).toInt() and 0xFF) == 0x09) {
                buf.get()
                break
            }
            val valObj = readAmf0Value(buf)
            if (key.isNotEmpty()) {
                map[key] = valObj
            }
        }
        return map
    }

    // ── Byte helpers ──
    private fun readUint24(dis: DataInputStream): Int {
        val b1 = dis.readUnsignedByte()
        val b2 = dis.readUnsignedByte()
        val b3 = dis.readUnsignedByte()
        return (b1 shl 16) or (b2 shl 8) or b3
    }

    private fun readInt32LE(dis: DataInputStream): Int {
        val b1 = dis.readUnsignedByte()
        val b2 = dis.readUnsignedByte()
        val b3 = dis.readUnsignedByte()
        val b4 = dis.readUnsignedByte()
        return b1 or (b2 shl 8) or (b3 shl 16) or (b4 shl 24)
    }

    private fun readUint32BE(dis: DataInputStream): Long {
        val b1 = dis.readUnsignedByte().toLong()
        val b2 = dis.readUnsignedByte().toLong()
        val b3 = dis.readUnsignedByte().toLong()
        val b4 = dis.readUnsignedByte().toLong()
        return (b1 shl 24) or (b2 shl 16) or (b3 shl 8) or b4
    }

    private fun writeUint32BE(out: OutputStream, v: Long) {
        out.write(((v ushr 24) and 0xFFL).toInt())
        out.write(((v ushr 16) and 0xFFL).toInt())
        out.write(((v ushr 8) and 0xFFL).toInt())
        out.write((v and 0xFFL).toInt())
    }

    private fun closeSocketQuietly() {
        try {
            input?.close()
        } catch (_: Throwable) {
        }
        try {
            output?.close()
        } catch (_: Throwable) {
        }
        try {
            socket?.close()
        } catch (_: Throwable) {
        }
        input = null
        output = null
        socket = null
    }
}
