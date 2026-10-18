package dev.sctvdl.flutter

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var playerEnvironment: PlayerEnvironment? = null
    private var files: FilesChannel? = null

    override fun onNewIntent(intent: Intent) {
        // Publish the new launch identity before plugins deliver asynchronous taps.
        setIntent(intent)
        super.onNewIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        playerEnvironment = PlayerEnvironment(this, messenger)
        files = FilesChannel(this, messenger)
    }

    override fun onDestroy() {
        try {
            playerEnvironment?.restore()
        } finally {
            files?.close()
            super.onDestroy()
        }
    }
}
