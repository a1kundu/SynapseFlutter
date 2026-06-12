package `in`.arijitk.synapse_flutter

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.StatFs
import android.os.storage.StorageManager
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "in.arijitk.synapse_flutter/shortcuts"
    private val FS_CHANNEL = "in.arijitk.synapse_flutter/file_system"
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

        // ── File system channel ──────────────────────────────────────────
        val fsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FS_CHANNEL)
        fsChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getStorageVolumes" -> {
                    result.success(getStorageVolumes())
                }
                "hasFilePermission" -> {
                    result.success(hasFilePermission())
                }
                "requestFilePermission" -> {
                    requestFilePermission()
                    result.success(true)
                }
                "getDiskUsage" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        result.success(getDiskUsage(path))
                    } else {
                        result.error("INVALID_ARGUMENT", "path is required", null)
                    }
                }
                else -> result.notImplemented()
            }
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

    // ── File system helpers ──────────────────────────────────────────────

    /**
     * Check if the app has broad file access.
     * On API 30+ this checks MANAGE_EXTERNAL_STORAGE.
     * On older APIs legacy READ/WRITE_EXTERNAL_STORAGE suffices.
     */
    private fun hasFilePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            true // legacy permissions declared in manifest
        }
    }

    /**
     * Open the system settings page to grant MANAGE_EXTERNAL_STORAGE.
     * On API < 30 this is a no-op since legacy permissions suffice.
     */
    private fun requestFilePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        }
    }

    /**
     * Enumerate all storage volumes (internal, SD card, USB) with their
     * paths, labels, and state.
     */
    private fun getStorageVolumes(): List<Map<String, Any?>> {
        val storageManager = getSystemService(Context.STORAGE_SERVICE) as StorageManager
        val volumes = storageManager.storageVolumes
        val result = mutableListOf<Map<String, Any?>>()

        // Get app-specific external dirs to derive volume root paths (works on all APIs)
        val externalDirs = ContextCompat.getExternalFilesDirs(this, null)

        for ((index, volume) in volumes.withIndex()) {
            val map = mutableMapOf<String, Any?>()
            map["description"] = volume.getDescription(this)
            map["isPrimary"] = volume.isPrimary
            map["isRemovable"] = volume.isRemovable
            map["isEmulated"] = volume.isEmulated
            map["state"] = volume.state

            // Determine type label
            map["type"] = when {
                volume.isPrimary -> "internal"
                volume.isRemovable && !volume.isEmulated -> "removable" // SD card or USB
                else -> "other"
            }

            // Get root path
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                map["path"] = volume.directory?.absolutePath
            } else {
                // Derive root from external files dir:
                //   /storage/emulated/0/Android/data/<pkg>/files -> /storage/emulated/0
                if (index < externalDirs.size && externalDirs[index] != null) {
                    val extDir = externalDirs[index]!!.absolutePath
                    val marker = "/Android/data/"
                    val rootEnd = extDir.indexOf(marker)
                    if (rootEnd > 0) {
                        map["path"] = extDir.substring(0, rootEnd)
                    }
                }
            }

            result.add(map)
        }

        return result
    }

    /**
     * Get disk usage stats for the volume containing the given path.
     * Returns total, free, and used bytes via StatFs.
     */
    private fun getDiskUsage(path: String): Map<String, Any> {
        val stat = StatFs(path)
        val totalBytes = stat.totalBytes
        val freeBytes = stat.availableBytes
        val usedBytes = totalBytes - freeBytes
        return mapOf(
            "total" to totalBytes,
            "free" to freeBytes,
            "used" to usedBytes
        )
    }

    companion object {
        private const val ACTION_CHECK_UPDATE = "in.arijitk.synapse_flutter.CHECK_UPDATE"
        private const val ACTION_OPEN_SETTINGS = "in.arijitk.synapse_flutter.OPEN_SETTINGS"
    }
}
