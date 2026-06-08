package `in`.arijitk.synapse_flutter

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "in.arijitk.synapse_flutter/shortcuts"
    private var pendingShortcut: String? = null
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        // If a shortcut intent arrived before the engine was ready, send it now.
        pendingShortcut?.let { action ->
            methodChannel?.invokeMethod("shortcutAction", action)
            pendingShortcut = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleShortcutIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShortcutIntent(intent)
    }

    private fun handleShortcutIntent(intent: Intent?) {
        val action = intent?.action ?: return
        val shortcutAction = when (action) {
            "in.arijitk.synapse_flutter.CHECK_UPDATE" -> "check_update"
            "in.arijitk.synapse_flutter.OPEN_SETTINGS" -> "open_settings"
            else -> null
        }
        if (shortcutAction != null) {
            if (methodChannel != null) {
                methodChannel?.invokeMethod("shortcutAction", shortcutAction)
            } else {
                // Engine not ready yet; stash it for configureFlutterEngine.
                pendingShortcut = shortcutAction
            }
        }
    }
}
