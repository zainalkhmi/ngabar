package com.ngabar.app

import android.content.Context
import android.graphics.Color
import android.media.MediaPlayer
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.VideoView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class NgabarVideoPlayerFactory(
    private val messenger: BinaryMessenger
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?>
        val path = params?.get("path") as? String ?: ""
        return NgabarVideoPlayerView(context, messenger, viewId, path)
    }
}

private class NgabarVideoPlayerView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    path: String
) : PlatformView, MethodChannel.MethodCallHandler {

    private val container = FrameLayout(context).apply {
        setBackgroundColor(Color.BLACK)
    }
    private val videoView = VideoView(context)
    private val channel = MethodChannel(messenger, "com.ngabar.app/video_player_$viewId")
    private var prepared = false
    private var disposed = false

    init {
        val lp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
            Gravity.CENTER
        )
        container.addView(videoView, lp)
        channel.setMethodCallHandler(this)

        videoView.setOnPreparedListener { mp: MediaPlayer ->
            if (disposed) return@setOnPreparedListener
            prepared = true
            mp.isLooping = false
            // Show first frame immediately
            try {
                videoView.seekTo(1)
            } catch (_: Throwable) {
            }
            channel.invokeMethod(
                "onPrepared",
                mapOf(
                    "durationMs" to mp.duration,
                    "width" to mp.videoWidth,
                    "height" to mp.videoHeight
                )
            )
        }

        videoView.setOnCompletionListener {
            if (disposed) return@setOnCompletionListener
            channel.invokeMethod("onCompleted", null)
        }

        videoView.setOnErrorListener { _, what, extra ->
            if (!disposed) {
                channel.invokeMethod("onError", "Video error ($what/$extra)")
            }
            true
        }

        if (path.isNotEmpty()) {
            videoView.setVideoPath(path)
        }
    }

    override fun getView(): View = container

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "play" -> {
                if (prepared) {
                    videoView.start()
                }
                result.success(prepared)
            }
            "pause" -> {
                if (videoView.canPause()) {
                    videoView.pause()
                }
                result.success(true)
            }
            "seekTo" -> {
                val ms = call.argument<Int>("positionMs") ?: 0
                if (prepared) {
                    videoView.seekTo(ms)
                }
                result.success(true)
            }
            "getPosition" -> {
                val pos = if (prepared) videoView.currentPosition else 0
                result.success(pos)
            }
            "isPlaying" -> {
                result.success(videoView.isPlaying)
            }
            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        try {
            videoView.stopPlayback()
        } catch (_: Throwable) {
        }
    }
}
