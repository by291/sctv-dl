package dev.sctvdl.flutter

import android.content.Intent
import android.content.res.Configuration
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val LOG_TAG = "SctvFlutterActivity"

class MainActivity : FlutterActivity() {
    private var playerEnvironment: PlayerEnvironment? = null
    private var files: FilesChannel? = null
    private var pictureInPictureEvents: MethodChannel? = null

    override fun onNewIntent(intent: Intent) {
        // Publish the new launch identity before plugins deliver asynchronous taps.
        setIntent(intent)
        super.onNewIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        pictureInPictureEvents = MethodChannel(messenger, "dev.sctvdl.flutter/picture_in_picture")
        playerEnvironment = PlayerEnvironment(this, messenger)
        files = FilesChannel(this, messenger)
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)

        // Configuration callbacks can precede the committed PiP state. The
        // Activity callback is authoritative and uses our own public contract.
        pictureInPictureEvents?.invokeMethod("changed", isInPictureInPictureMode)
    }

    override fun onStop() {
        super.onStop()

        // A visible PiP Activity is paused but not stopped. Closing its system
        // window must stop audio even when Flutter was already backgrounded.
        pictureInPictureEvents?.invokeMethod("stopped", null)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        val player = playerEnvironment
        val fileChannel = files
        playerEnvironment = null
        files = null
        pictureInPictureEvents = null

        // The engine still needs to detach its plugins after this callback returns.
        runCatching { player?.close() }
            .onFailure { error -> Log.e(LOG_TAG, "Player environment cleanup failed", error) }
        runCatching { fileChannel?.close() }
            .onFailure { error -> Log.e(LOG_TAG, "File channel cleanup failed", error) }

        super.cleanUpFlutterEngine(flutterEngine)
    }
}
