package lingxue.flsqliteviewer

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import lingxue.flsqliteviewer.fileaccess.ShizukuFileAccess
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import rikka.shizuku.Shizuku

class MainActivity : FlutterActivity() {
    private var pendingShizukuPermissionResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val storageExecutor = Executors.newCachedThreadPool()
    private val launchStartElapsedMs = SystemClock.elapsedRealtime()

    private val shizukuPermissionListener =
        Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
            if (requestCode != REQUEST_CODE_SHIZUKU) return@OnRequestPermissionResultListener
            val granted = grantResult == PackageManager.PERMISSION_GRANTED
            RootFileAccess.cachedShizukuPermission = granted
            RootFileAccess.cachedShizukuPermissionAt = System.currentTimeMillis()
            pendingShizukuPermissionResult?.success(granted)
            pendingShizukuPermissionResult = null
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.i(TAG, "startup onCreate +${SystemClock.elapsedRealtime() - launchStartElapsedMs}ms")
        super.onCreate(savedInstanceState)
    }

    override fun onDestroy() {
        pendingShizukuPermissionResult = null
        runCatching { Shizuku.removeRequestPermissionResultListener(shizukuPermissionListener) }
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        runCatching { Shizuku.addRequestPermissionResultListener(shizukuPermissionListener) }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STORAGE_ACCESS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasManageAllFilesAccess" -> result.success(hasManageAllFilesAccess())
                "openManageAllFilesAccessSettings" -> {
                    openManageAllFilesAccessSettings(); result.success(null)
                }
                "isShizukuAvailable" -> result.success(RootFileAccess.isShizukuAvailable(this))
                "hasShizukuPermission" -> {
                    val forceRefresh = call.argument<Boolean>("forceRefresh") == true
                    result.success(RootFileAccess.hasShizukuPermission(this, forceRefresh))
                }
                "getShizukuStatus" -> {
                    val forceRefresh = call.argument<Boolean>("forceRefresh") == true
                    result.success(
                        mapOf(
                            "installed" to RootFileAccess.isShizukuInstalled(this),
                            "running" to RootFileAccess.isShizukuAvailable(this),
                            "permissionGranted" to RootFileAccess.hasShizukuPermission(this, forceRefresh),
                        ),
                    )
                }
                "openShizukuApp" -> { openShizukuApp(); result.success(null) }
                "requestShizukuPermission" -> handleShizukuPermissionRequest(result)
                "hasRootAccess" -> runStorageTask(result, "root_check_failed", "Root check failed") {
                    val forceRefresh = call.argument<Boolean>("forceRefresh") == true
                    RootFileAccess.hasRootAccess(storageExecutor, forceRefresh)
                }
                "listDirectoryEntriesWithRoot" -> {
                    val path = call.argument<String>("path") ?: return@setMethodCallHandler result.error("invalid_path", "path required", null)
                    runStorageTask(result, "root_list_failed", "Root directory listing failed") {
                        RootFileAccess.listDirectoryEntries(storageExecutor, path.trim())
                    }
                }
                "readFileWithRoot" -> {
                    val path = call.argument<String>("path") ?: return@setMethodCallHandler result.error("invalid_path", "path required", null)
                    runStorageTask(result, "root_read_failed", "Root file read failed") {
                        RootFileAccess.readFile(storageExecutor, path.trim())
                    }
                }
                "writeFileWithRoot" -> {
                    val path = call.argument<String>("path") ?: return@setMethodCallHandler result.error("invalid_path", "path required", null)
                    val bytes = call.argument<ByteArray>("bytes") ?: return@setMethodCallHandler result.error("invalid_data", "bytes required", null)
                    runStorageTask(result, "root_write_failed", "Root file write failed") {
                        RootFileAccess.writeFile(storageExecutor, path.trim(), bytes)
                        null
                    }
                }
                "existsWithRoot" -> {
                    val path = call.argument<String>("path") ?: return@setMethodCallHandler result.success(false)
                    runStorageTask(result, "root_exists_failed", "Root exists check failed") {
                        RootFileAccess.exists(storageExecutor, path.trim())
                    }
                }
                "listDirectoryEntriesWithShizuku" -> {
                    val path = call.argument<String>("path") ?: return@setMethodCallHandler result.error("invalid_path", "path required", null)
                    runStorageTask(result, "shizuku_list_failed", "Shizuku directory listing failed") {
                        ShizukuFileAccess.listDirectoryEntries(this, storageExecutor, path.trim())
                    }
                }
                "readFileWithShizuku" -> {
                    val path = call.argument<String>("path") ?: return@setMethodCallHandler result.error("invalid_path", "path required", null)
                    runStorageTask(result, "shizuku_read_failed", "Shizuku file read failed") {
                        ShizukuFileAccess.readFile(this, storageExecutor, path.trim())
                    }
                }
                "writeFileWithShizuku" -> {
                    val path = call.argument<String>("path") ?: return@setMethodCallHandler result.error("invalid_path", "path required", null)
                    val bytes = call.argument<ByteArray>("bytes") ?: return@setMethodCallHandler result.error("invalid_data", "bytes required", null)
                    runStorageTask(result, "shizuku_write_failed", "Shizuku file write failed") {
                        ShizukuFileAccess.writeFile(this, storageExecutor, path.trim(), bytes)
                        null
                    }
                }
                "existsWithShizuku" -> {
                    val path = call.argument<String>("path") ?: return@setMethodCallHandler result.success(false)
                    runStorageTask(result, "shizuku_exists_failed", "Shizuku exists check failed") {
                        ShizukuFileAccess.exists(this, storageExecutor, path.trim())
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun <T> runStorageTask(result: MethodChannel.Result, errorCode: String, fallbackMessage: String, block: () -> T) {
        storageExecutor.execute {
            runCatching { block() }
                .onSuccess { value -> mainHandler.post { result.success(value) } }
                .onFailure { error -> mainHandler.post { result.error(errorCode, error.message ?: fallbackMessage, null) } }
        }
    }

    private fun handleShizukuPermissionRequest(result: MethodChannel.Result) {
        if (!RootFileAccess.isShizukuAvailable(this)) { result.success(false); return }
        if (RootFileAccess.hasShizukuPermission(this)) { result.success(true); return }
        if (pendingShizukuPermissionResult != null) { result.error("busy", "shizuku permission request already in progress", null); return }
        pendingShizukuPermissionResult = result
        runCatching { Shizuku.requestPermission(REQUEST_CODE_SHIZUKU) }
            .onFailure {
                pendingShizukuPermissionResult = null
                result.error("shizuku_request_failed", it.message ?: "failed to request shizuku permission", null)
            }
    }

    private fun hasManageAllFilesAccess(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.R || Environment.isExternalStorageManager()

    private fun openManageAllFilesAccessSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val appIntent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply { data = Uri.parse("package:$packageName") }
        runCatching { startActivity(appIntent) }
            .onFailure { startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)) }
    }

    private fun openShizukuApp() {
        val launchIntent =
            packageManager.getLaunchIntentForPackage("moe.shizuku.privileged.api")
                ?: packageManager.getLaunchIntentForPackage("moe.shizuku.manager")
        if (launchIntent != null) { startActivity(launchIntent); return }
        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:moe.shizuku.privileged.api")
        })
    }

    companion object {
        private const val TAG = "FlSQLiteViewer"
        private const val STORAGE_ACCESS_CHANNEL = "lingxue.flsqliteviewer/storage_access"
        private const val REQUEST_CODE_SHIZUKU = 52001
    }
}