package com.ngabar.app

import android.app.Activity
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.MediaStore
import android.util.DisplayMetrics
import android.view.WindowManager
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import com.cloudwebrtc.webrtc.audio.AudioSwitchManager
// TODO(playstore-fgs): Restore AudioServiceActivity when re-enabling FOREGROUND_SERVICE_MEDIA_PLAYBACK.
// import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.ngabar.app/playstore"
    private val MAGLIS_SERVICE_CHANNEL = "com.ngabar.app/maglis_service"
    private val LIFECYCLE_CHANNEL = "com.ngabar.app/audio_lifecycle"
    private val SCREEN_RECORD_CHANNEL = "com.ngabar.app/screen_record"

    companion object {
        private const val REQ_SCREEN_RECORD = 9401
    }

    private var screenRecordChannel: MethodChannel? = null
    private var pendingScreenRecordResult: MethodChannel.Result? = null
    private var pendingOutputPath: String = ""
    private var pendingRtmpUrl: String = ""
    private var pendingEncoderProfile: String = "recording"
    private var pendingCaptureMic: Boolean = true
    private var pendingInMaglis: Boolean = false
    private var pendingExternalMicActive: Boolean = false

    private var isScreenOff = false

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> isScreenOff = true
                Intent.ACTION_SCREEN_ON, Intent.ACTION_USER_PRESENT -> isScreenOff = false
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep screen awake continuously while app is in foreground (Standard Android Window Flag)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        WindowCompat.setDecorFitsSystemWindows(window, false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.attributes.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            @Suppress("DEPRECATION")
            window.attributes.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        ContextCompat.registerReceiver(this, screenReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(screenReceiver)
        } catch (_: Exception) {}
        ScreenRecordService.onStateChanged = null
        if (isFinishing && ScreenRecordService.isCurrentlyRecording) {
            try {
                val stopIntent = Intent(this, ScreenRecordService::class.java).apply {
                    action = ScreenRecordService.ACTION_STOP
                }
                startService(stopIntent)
            } catch (_: Exception) {}
        }
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "com.ngabar.app/video_player",
                NgabarVideoPlayerFactory(flutterEngine.dartExecutor.binaryMessenger)
            )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "isPlayStoreInstalled") {
                Thread {
                    val isInstalled = isPackageInstalled("com.android.vending")
                    runOnUiThread {
                        result.success(isInstalled)
                    }
                }.start()
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LIFECYCLE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "isScreenOffOrLocked") {
                val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                val isInteractive = powerManager?.isInteractive ?: true
                val isLocked = keyguardManager?.isKeyguardLocked ?: false
                result.success((!isInteractive) || isLocked || isScreenOff)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MAGLIS_SERVICE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    // TODO(playstore-fgs): Temporarily no-op while FOREGROUND_SERVICE_MICROPHONE is disabled.
                    result.success(true)
                }
                "stopService" -> {
                    // TODO(playstore-fgs): Temporarily no-op while FOREGROUND_SERVICE_MICROPHONE is disabled.
                    result.success(true)
                }
                "resetAudioToNormal" -> {
                    try {
                        AudioSwitchManager.instance?.stop()
                    } catch (_: Throwable) {
                    }
                    Handler(Looper.getMainLooper()).post {
                        try {
                            val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                            if (am != null) {
                                @Suppress("DEPRECATION")
                                am.isSpeakerphoneOn = false
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                    try {
                                        am.clearCommunicationDevice()
                                    } catch (_: Throwable) {
                                    }
                                }
                                try {
                                    @Suppress("DEPRECATION")
                                    if (am.isBluetoothScoOn) {
                                        am.stopBluetoothSco()
                                        am.isBluetoothScoOn = false
                                    }
                                } catch (_: Throwable) {
                                }
                                am.mode = AudioManager.MODE_NORMAL
                            }
                        } catch (_: Throwable) {
                        }
                        result.success(true)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        val srChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_RECORD_CHANNEL)
        screenRecordChannel = srChannel
        ScreenRecordService.onStateChanged = { isRecording, filePath, durationMs, error ->
            srChannel.invokeMethod(
                "onStateChanged",
                mapOf(
                    "isRecording" to isRecording,
                    "filePath" to filePath,
                    "durationMs" to durationMs,
                    "error" to error
                )
            )
        }
        ScreenRecordService.onLiveStateChanged = { status, bitrateKbps, droppedFrames, error ->
            srChannel.invokeMethod(
                "onLiveStateChanged",
                mapOf(
                    "status" to status,
                    "bitrateKbps" to bitrateKbps,
                    "droppedFrames" to droppedFrames,
                    "error" to error
                )
            )
        }

        srChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startScreenRecord" -> {
                    if (ScreenRecordService.isCurrentlyRecording) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    if (pendingScreenRecordResult != null) {
                        result.error("BUSY", "Screen record prompt already open", null)
                        return@setMethodCallHandler
                    }
                    val path = call.argument<String>("outputPath") ?: ""
                    if (path.isEmpty()) {
                        result.error("INVALID_ARGS", "outputPath is required", null)
                        return@setMethodCallHandler
                    }
                    pendingOutputPath = path
                    pendingRtmpUrl = ""
                    pendingEncoderProfile = "recording"
                    pendingCaptureMic = call.argument<Boolean>("captureMic") ?: true
                    pendingInMaglis = call.argument<Boolean>("inMaglis") ?: false
                    pendingExternalMicActive = call.argument<Boolean>("externalMicActive") ?: false
                    pendingScreenRecordResult = result

                    val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    @Suppress("DEPRECATION")
                    startActivityForResult(mpm.createScreenCaptureIntent(), REQ_SCREEN_RECORD)
                }
                "startLiveStream" -> {
                    if (ScreenRecordService.isCurrentlyRecording) {
                        result.error("BUSY", "Sedang merekam atau live streaming", null)
                        return@setMethodCallHandler
                    }
                    if (pendingScreenRecordResult != null) {
                        result.error("BUSY", "Screen capture prompt already open", null)
                        return@setMethodCallHandler
                    }
                    val rtmpUrl = call.argument<String>("rtmpUrl") ?: ""
                    if (rtmpUrl.isEmpty()) {
                        result.error("INVALID_ARGS", "rtmpUrl is required", null)
                        return@setMethodCallHandler
                    }
                    pendingOutputPath = ""
                    pendingRtmpUrl = rtmpUrl
                    pendingEncoderProfile = call.argument<String>("encoderProfile") ?: "light"
                    pendingCaptureMic = call.argument<Boolean>("captureMic") ?: true
                    pendingInMaglis = call.argument<Boolean>("inMaglis") ?: false
                    pendingExternalMicActive = call.argument<Boolean>("externalMicActive") ?: false
                    pendingScreenRecordResult = result

                    val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    @Suppress("DEPRECATION")
                    startActivityForResult(mpm.createScreenCaptureIntent(), REQ_SCREEN_RECORD)
                }
                "stopScreenRecord", "stopLiveStream" -> {
                    if (!ScreenRecordService.isCurrentlyRecording) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    val stopIntent = Intent(this, ScreenRecordService::class.java).apply {
                        action = ScreenRecordService.ACTION_STOP
                    }
                    startService(stopIntent)
                    result.success(true)
                }
                "appendMicPcm" -> {
                    val bytes = call.argument<ByteArray>("pcm")
                    if (bytes != null) {
                        ScreenRecordService.appendExternalMicPcm16(bytes)
                    }
                    result.success(null)
                }
                "setAudioContext" -> {
                    val extActive = call.argument<Boolean>("externalMicActive") ?: false
                    val maglis = call.argument<Boolean>("inMaglis") ?: false
                    ScreenRecordService.updateAudioContext(extActive, maglis)
                    result.success(true)
                }
                "isRecording" -> {
                    result.success(ScreenRecordService.isCurrentlyRecording)
                }
                "saveVideoToGallery" -> {
                    val srcPath = call.argument<String>("filePath") ?: ""
                    val displayName = call.argument<String>("displayName") ?: "ngabar_recording.mp4"
                    Thread {
                        val ok = saveVideoFileToGallery(srcPath, displayName)
                        runOnUiThread { result.success(ok) }
                    }.start()
                }
                "getInstalledSocialApps" -> {
                    result.success(
                        mapOf(
                            "youtube" to (findInstalledSocialPackage("youtube") != null),
                            "tiktok" to (findInstalledSocialPackage("tiktok") != null),
                            "facebook" to (findInstalledSocialPackage("facebook") != null)
                        )
                    )
                }
                "shareToSocialPlatform" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val platform = call.argument<String>("platform") ?: ""
                    val caption = call.argument<String>("caption") ?: ""
                    val title = call.argument<String>("title") ?: "ngabar"
                    Thread {
                        val preparedUri = prepareShareableVideoUri(filePath)
                        runOnUiThread {
                            if (preparedUri == null) {
                                result.success(false)
                            } else {
                                val launched = launchSocialVideoShare(
                                    contentUri = preparedUri,
                                    platform = platform,
                                    caption = caption,
                                    title = title
                                )
                                result.success(launched)
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_SCREEN_RECORD) {
            val pendingResult = pendingScreenRecordResult
            pendingScreenRecordResult = null

            if (resultCode != Activity.RESULT_OK || data == null) {
                pendingResult?.success(false)
                return
            }

            val (recW, recH, dpi) = computeRecordingDimensions(pendingEncoderProfile)
            ScreenRecordService.pendingResultCode = resultCode
            ScreenRecordService.pendingResultData = data

            val serviceIntent = Intent(this, ScreenRecordService::class.java).apply {
                action = ScreenRecordService.ACTION_START
                putExtra(ScreenRecordService.EXTRA_OUTPUT_PATH, pendingOutputPath)
                putExtra(ScreenRecordService.EXTRA_RTMP_URL, pendingRtmpUrl)
                putExtra(ScreenRecordService.EXTRA_ENCODER_PROFILE, pendingEncoderProfile)
                putExtra(ScreenRecordService.EXTRA_WIDTH, recW)
                putExtra(ScreenRecordService.EXTRA_HEIGHT, recH)
                putExtra(ScreenRecordService.EXTRA_DPI, dpi)
                putExtra(ScreenRecordService.EXTRA_CAPTURE_MIC, pendingCaptureMic)
                putExtra(ScreenRecordService.EXTRA_IN_MAGLIS, pendingInMaglis)
                putExtra(ScreenRecordService.EXTRA_EXTERNAL_MIC_ACTIVE, pendingExternalMicActive)
            }
            ContextCompat.startForegroundService(this, serviceIntent)
            pendingResult?.success(true)
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun computeRecordingDimensions(encoderProfile: String): Triple<Int, Int, Int> {
        val rawW: Int
        val rawH: Int
        val dpi: Int

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.currentWindowMetrics.bounds
            rawW = bounds.width()
            rawH = bounds.height()
            dpi = resources.configuration.densityDpi
        } else {
            val dm = DisplayMetrics()
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getRealMetrics(dm)
            rawW = dm.widthPixels
            rawH = dm.heightPixels
            dpi = dm.densityDpi
        }

        val isLight = encoderProfile == "light"
        val maxLimit = if (isLight) 960.0 else 1280.0
        val maxSide = max(rawW, rawH).toDouble()
        val scale = if (maxSide > maxLimit) maxLimit / maxSide else 1.0
        val targetW = max(320, ((rawW * scale) / 16.0).roundToInt() * 16)
        val targetH = max(320, ((rawH * scale) / 16.0).roundToInt() * 16)
        val maxDpi = if (isLight) 320 else 480
        return Triple(targetW, targetH, min(dpi, maxDpi))
    }

    private fun saveVideoFileToGallery(srcPath: String, displayName: String): Boolean {
        if (srcPath.isEmpty()) return false
        val srcFile = File(srcPath)
        if (!srcFile.exists() || !srcFile.isFile) return false

        val safeName = if (displayName.endsWith(".mp4", ignoreCase = true)) {
            displayName
        } else {
            "$displayName.mp4"
        }

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Video.Media.DISPLAY_NAME, safeName)
                    put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                    put(MediaStore.Video.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MOVIES}/Ngabar")
                    put(MediaStore.Video.Media.IS_PENDING, 1)
                }
                val resolver = contentResolver
                val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
                    ?: return false

                resolver.openOutputStream(uri)?.use { out ->
                    FileInputStream(srcFile).use { input ->
                        input.copyTo(out)
                    }
                } ?: return false

                values.clear()
                values.put(MediaStore.Video.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                true
            } else {
                @Suppress("DEPRECATION")
                val moviesDir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
                    "Ngabar"
                )
                if (!moviesDir.exists()) moviesDir.mkdirs()
                val destFile = File(moviesDir, safeName)
                srcFile.copyTo(destFile, overwrite = true)
                true
            }
        } catch (_: Throwable) {
            false
        }
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            packageManager.getPackageInfo(packageName, 0)

            // Validate that the app was actually installed by Google Play Store.
            // Sideloaded apps or alternative stores (like MicroG environments)
            // will crash or fail if Play Core APIs are invoked.
            val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                packageManager.getInstallSourceInfo(context.packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstallerPackageName(context.packageName)
            }

            installer == packageName
        } catch (e: Exception) {
            false
        }
    }

    private fun findInstalledSocialPackage(platform: String): String? {
        val candidates = when (platform.lowercase()) {
            "youtube" -> listOf("com.google.android.youtube")
            "tiktok" -> listOf("com.zhiliaoapp.musically", "com.ss.android.ugc.trill")
            "facebook" -> listOf("com.facebook.katana", "com.facebook.lite")
            else -> emptyList()
        }
        for (pkg in candidates) {
            try {
                packageManager.getPackageInfo(pkg, 0)
                return pkg
            } catch (_: Throwable) {
            }
        }
        return null
    }

    private fun prepareShareableVideoUri(srcPath: String): Uri? {
        if (srcPath.isEmpty()) return null
        val srcFile = File(srcPath)
        if (!srcFile.exists() || !srcFile.isFile) return null
        val authority = "$packageName.ngabar.fileprovider"

        // Try direct FileProvider URI first
        try {
            return FileProvider.getUriForFile(this, authority, srcFile)
        } catch (_: Throwable) {
        }

        // Otherwise stage cleanly into cacheDir/shared_videos (covered by <cache-path>)
        return try {
            val shareDir = File(cacheDir, "shared_videos")
            if (!shareDir.exists()) shareDir.mkdirs()
            // Remove older staged files so cache never grows unbounded
            shareDir.listFiles()?.forEach { old ->
                if (old.isFile && old.name != srcFile.name) {
                    old.delete()
                }
            }
            val dest = File(shareDir, srcFile.name)
            if (!dest.exists() || dest.length() != srcFile.length()) {
                srcFile.copyTo(dest, overwrite = true)
            }
            FileProvider.getUriForFile(this, authority, dest)
        } catch (_: Throwable) {
            null
        }
    }

    private fun launchSocialVideoShare(
        contentUri: Uri,
        platform: String,
        caption: String,
        title: String
    ): Boolean {
        val pkg = findInstalledSocialPackage(platform) ?: return false

        if (caption.isNotEmpty()) {
            try {
                val cm = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                cm?.setPrimaryClip(ClipData.newPlainText("ngabar_caption", caption))
            } catch (_: Throwable) {
            }
        }

        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = "video/mp4"
            putExtra(Intent.EXTRA_STREAM, contentUri)
            putExtra(Intent.EXTRA_SUBJECT, title)
            if (caption.isNotEmpty()) {
                putExtra(Intent.EXTRA_TEXT, caption)
            }
            clipData = ClipData.newRawUri("ngabar_video", contentUri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            setPackage(pkg)
        }

        return try {
            val resolved = shareIntent.resolveActivity(packageManager) ?: return false
            grantUriPermission(
                resolved.packageName,
                contentUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
            startActivity(shareIntent)
            true
        } catch (_: Throwable) {
            false
        }
    }
}
