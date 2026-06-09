package `in`.arijitk.synapse_flutter

import android.content.Intent
import android.os.Bundle
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
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
        registerShortcuts()
        handleShortcutIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShortcutIntent(intent)
    }

    /**
     * Register dynamic shortcuts so that `packageName` (the runtime applicationId)
     * is always correct — works for debug (.debug), PR (.prN), and release builds.
     */
    private fun registerShortcuts() {
        val checkUpdate = ShortcutInfoCompat.Builder(this, "check_update")
            .setShortLabel(getString(R.string.shortcut_check_update_short))
            .setLongLabel(getString(R.string.shortcut_check_update_long))
            .setIcon(IconCompat.createWithResource(this, R.drawable.ic_shortcut_update))
            .setIntent(
                Intent(this, MainActivity::class.java).apply {
                    action = ACTION_CHECK_UPDATE
                }
            )
            .build()

        val openSettings = ShortcutInfoCompat.Builder(this, "open_settings")
            .setShortLabel(getString(R.string.shortcut_open_settings_short))
            .setLongLabel(getString(R.string.shortcut_open_settings_long))
            .setIcon(IconCompat.createWithResource(this, R.drawable.ic_shortcut_settings))
            .setIntent(
                Intent(this, MainActivity::class.java).apply {
                    action = ACTION_OPEN_SETTINGS
                }
            )
            .build()

        ShortcutManagerCompat.setDynamicShortcuts(this, listOf(checkUpdate, openSettings))
    }

    private fun handleShortcutIntent(intent: Intent?) {
        val action = intent?.action ?: return
        val shortcutAction = when (action) {
            ACTION_CHECK_UPDATE -> "check_update"
            ACTION_OPEN_SETTINGS -> "open_settings"
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

    companion object {
        private const val ACTION_CHECK_UPDATE = "in.arijitk.synapse_flutter.CHECK_UPDATE"
        private const val ACTION_OPEN_SETTINGS = "in.arijitk.synapse_flutter.OPEN_SETTINGS"
    }
}
