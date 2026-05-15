package lingxue.flsqliteviewer

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import lingxue.flsqliteviewer.fileaccess.ShizukuFileAccess
import lingxue.flsqliteviewer.shizuku.FlSqlViewerShizukuFileService
import lingxue.flsqliteviewer.shizuku.IFlSqlViewerShizukuFileService
import java.util.concurrent.Executors
import rikka.shizuku.Shizuku

class MainActivity : FlutterActivity() {
    private var pendingShizukuPermissionResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val storageExecutor = Executors.newCachedThreadPool()
    private val launchStartElapsedMs = SystemClock.elapsedRealtime()
    private val shizukuUserServiceLock = java.lang.Object()

    @Volatile
    private var shizukuUserService: IFlSqlViewerShizukuFileService? = null

    @Volatile
    private var shizukuUserServiceBinding = false

    private val shizukuUserServiceArgs by lazy {
        Shizuku.UserServiceArgs(
            ComponentName(packageName, FlSqlViewerShizukuFileService::class.java.name),
        ).processNameSuffix("shizuku_fs")
            .debuggable(
                (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0,
            )
            .version(1)
            .tag("flsqlviewer_fs")
    }

    private val shizukuPermissionListener =
        Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
            if (requestCode != REQUEST_CODE_SHIZUKU) return@OnRequestPermissionResultListener
            val granted = grantResult == PackageManager.PERMISSION_GRANTED
            RootFileAccess.cachedShizukuPermission = granted
            RootFileAccess.cachedShizukuPermissionAt = System.currentTimeMillis()
            if (granted) {
                ensureShizukuUserServiceBoundAsync()
            } else {
                clearShizukuUserService()
            }
            pendingShizukuPermissionResult?.success(granted)
            pendingShizukuPermissionResult = null
        }

    private val shizukuBinderReceivedListener =
        Shizuku.OnBinderReceivedListener {
            ensureShizukuUserServiceBoundAsync()
        }

    private val shizukuBinderDeadListener =
        Shizuku.OnBinderDeadListener {
            clearShizukuUserService()
        }

    private val shizukuUserServiceConnection =
        object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, service: IBinder) {
                synchronized(shizukuUserServiceLock) {
                    shizukuUserService = IFlSqlViewerShizukuFileService.Stub.asInterface(service)
                    shizukuUserServiceBinding = false
                    shizukuUserServiceLock.notifyAll()
                }
            }

            override fun onServiceDisconnected(name: ComponentName) {
                clearShizukuUserService()
            }

            override fun onBindingDied(name: ComponentName) {
                clearShizukuUserService()
            }

            override fun onNullBinding(name: ComponentName) {
                clearShizukuUserService()
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.i(TAG, "startup onCreate +${SystemClock.elapsedRealtime() - launchStartElapsedMs}ms")
        super.onCreate(savedInstanceState)
    }

    override fun onDestroy() {
        pendingShizukuPermissionResult = null
        runCatching { Shizuku.removeRequestPermissionResultListener(shizukuPermissionListener) }
        runCatching { Shizuku.removeBinderReceivedListener(shizukuBinderReceivedListener) }
        runCatching { Shizuku.removeBinderDeadListener(shizukuBinderDeadListener) }
        runCatching {
            Shizuku.unbindUserService(shizukuUserServiceArgs, shizukuUserServiceConnection, false)
        }
        clearShizukuUserService()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        runCatching {
            Shizuku.addRequestPermissionResultListener(shizukuPermissionListener)
            Shizuku.addBinderReceivedListenerSticky(shizukuBinderReceivedListener)
            Shizuku.addBinderDeadListener(shizukuBinderDeadListener)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STORAGE_ACCESS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasManageAllFilesAccess" -> result.success(hasManageAllFilesAccess())
                "openManageAllFilesAccessSettings" -> {
                    openManageAllFilesAccessSettings()
                    result.success(null)
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
                "openShizukuApp" -> {
                    openShizukuApp()
                    result.success(null)
                }
                "requestShizukuPermission" -> handleShizukuPermissionRequest(result)
                "hasRootAccess" -> runStorageTask(result, "root_check_failed", "Root check failed") {
                    val forceRefresh = call.argument<Boolean>("forceRefresh") == true
                    RootFileAccess.hasRootAccess(storageExecutor, forceRefresh)
                }
                "listDirectoryEntriesWithRoot" -> {
                    val path = call.argument<String>("path")
                        ?: return@setMethodCallHandler result.error("invalid_path", "path required", null)
                    runStorageTask(result, "root_list_failed", "Root directory listing failed") {
                        RootFileAccess.listDirectoryEntries(storageExecutor, path.trim())
                    }
                }
                "readFileWithRoot" -> {
                    val path = call.argument<String>("path")
                        ?: return@setMethodCallHandler result.error("invalid_path", "path required", null)
                    runStorageTask(result, "root_read_failed", "Root file read failed") {
                        RootFileAccess.readFile(storageExecutor, path.trim())
                    }
                }
                "writeFileWithRoot" -> {
                    val path = call.argument<String>("path")
                        ?: return@setMethodCallHandler result.error("invalid_path", "path required", null)
                    val bytes = call.argument<ByteArray>("bytes")
                        ?: return@setMethodCallHandler result.error("invalid_data", "bytes required", null)
                    runStorageTask(result, "root_write_failed", "Root file write failed") {
                        RootFileAccess.writeFile(storageExecutor, path.trim(), bytes)
                        null
                    }
                }
                "existsWithRoot" -> {
                    val path = call.argument<String>("path")
                        ?: return@setMethodCallHandler result.success(false)
                    runStorageTask(result, "root_exists_failed", "Root exists check failed") {
                        RootFileAccess.exists(storageExecutor, path.trim())
                    }
                }
                "listDirectoryEntriesWithShizuku" -> {
                    val path = call.argument<String>("path")
                        ?: return@setMethodCallHandler result.error("invalid_path", "path required", null)
                    runStorageTask(result, "shizuku_list_failed", "Shizuku directory listing failed") {
                        listDirectoryEntriesWithShizuku(path.trim())
                    }
                }
                "readFileWithShizuku" -> {
                    val path = call.argument<String>("path")
                        ?: return@setMethodCallHandler result.error("invalid_path", "path required", null)
                    runStorageTask(result, "shizuku_read_failed", "Shizuku file read failed") {
                        readFileWithShizuku(path.trim())
                    }
                }
                "writeFileWithShizuku" -> {
                    val path = call.argument<String>("path")
                        ?: return@setMethodCallHandler result.error("invalid_path", "path required", null)
                    val bytes = call.argument<ByteArray>("bytes")
                        ?: return@setMethodCallHandler result.error("invalid_data", "bytes required", null)
                    runStorageTask(result, "shizuku_write_failed", "Shizuku file write failed") {
                        writeFileWithShizuku(path.trim(), bytes)
                        null
                    }
                }
                "existsWithShizuku" -> {
                    val path = call.argument<String>("path")
                        ?: return@setMethodCallHandler result.success(false)
                    runStorageTask(result, "shizuku_exists_failed", "Shizuku exists check failed") {
                        existsWithShizuku(path.trim())
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun <T> runStorageTask(
        result: MethodChannel.Result,
        errorCode: String,
        fallbackMessage: String,
        block: () -> T,
    ) {
        storageExecutor.execute {
            runCatching { block() }
                .onSuccess { value -> mainHandler.post { result.success(value) } }
                .onFailure { error ->
                    val message = error.message ?: "$fallbackMessage: ${error::class.java.simpleName}"
                    Log.w(TAG, "$errorCode: $message", error)
                    mainHandler.post { result.error(errorCode, message, error.stackTraceToString()) }
                }
        }
    }

    private fun listDirectoryEntriesWithShizuku(path: String): List<Map<String, String>> {
        if (!RootFileAccess.hasShizukuPermission(this)) {
            throw IllegalStateException("Shizuku permission not granted")
        }
        return runCatching {
            withShizukuUserService { service ->
                parseDirectoryEntries(service.listEntries(path).asSequence())
            }
        }.getOrElse { error ->
            Log.w(TAG, "Shizuku UserService directory listing failed for $path", error)
            ShizukuFileAccess.listDirectoryEntries(this, storageExecutor, path)
        }
    }

    private fun readFileWithShizuku(path: String): ByteArray {
        if (!RootFileAccess.hasShizukuPermission(this)) {
            throw IllegalStateException("Shizuku permission not granted")
        }
        return runCatching {
            withShizukuUserService { service ->
                service.readFile(path)
            }
        }.getOrElse { error ->
            Log.w(TAG, "Shizuku UserService file read failed for $path", error)
            ShizukuFileAccess.readFile(this, storageExecutor, path)
        }
    }

    private fun writeFileWithShizuku(path: String, bytes: ByteArray) {
        if (!RootFileAccess.hasShizukuPermission(this)) {
            throw IllegalStateException("Shizuku permission not granted")
        }
        runCatching {
            withShizukuUserService { service ->
                service.writeFile(path, bytes)
            }
        }.getOrElse { error ->
            Log.w(TAG, "Shizuku UserService file write failed for $path", error)
            ShizukuFileAccess.writeFile(this, storageExecutor, path, bytes)
        }
    }

    private fun existsWithShizuku(path: String): Boolean {
        if (!RootFileAccess.hasShizukuPermission(this)) {
            return false
        }
        return runCatching {
            withShizukuUserService { service ->
                service.fileExists(path)
            }
        }.getOrElse { error ->
            Log.w(TAG, "Shizuku UserService file exists failed for $path", error)
            ShizukuFileAccess.exists(this, storageExecutor, path)
        }
    }

    private fun parseDirectoryEntries(lines: Sequence<String>): List<Map<String, String>> {
        return lines
            .map { it.trimEnd() }
            .filter { it.isNotBlank() }
            .mapNotNull { rawLine ->
                val parts = rawLine.split('\t', limit = 2)
                if (parts.size != 2) {
                    null
                } else {
                    val type = parts[0].trim()
                    val name = parts[1].trim()
                    when {
                        name.isEmpty() || name == "." || name == ".." -> null
                        type != "directory" && type != "file" -> null
                        else -> mapOf("type" to type, "name" to name)
                    }
                }
            }.distinctBy { "${it["type"]}\u0000${it["name"]}" }
            .sortedWith(
                compareBy<Map<String, String>> { it["type"] != "directory" }
                    .thenBy { it["name"]?.lowercase() },
            ).toList()
    }

    private fun <T> withShizukuUserService(block: (IFlSqlViewerShizukuFileService) -> T): T {
        val service = getShizukuUserService() ?: throw IllegalStateException("Shizuku UserService not ready")
        return try {
            block(service)
        } catch (error: Throwable) {
            clearShizukuUserService()
            throw error
        }
    }

    private fun getShizukuUserService(
        timeoutMs: Long = SHIZUKU_USER_SERVICE_BIND_TIMEOUT_MS,
    ): IFlSqlViewerShizukuFileService? {
        if (!RootFileAccess.hasShizukuPermission(this)) {
            return null
        }
        shizukuUserService?.let { service ->
            if (service.asBinder()?.isBinderAlive == true) {
                return service
            }
        }
        bindShizukuUserServiceIfNeeded()
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        synchronized(shizukuUserServiceLock) {
            while (true) {
                shizukuUserService?.let { service ->
                    if (service.asBinder()?.isBinderAlive == true) {
                        return service
                    }
                }
                val remainingMs = deadline - SystemClock.elapsedRealtime()
                if (remainingMs <= 0L) {
                    return null
                }
                try {
                    shizukuUserServiceLock.wait(remainingMs)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return null
                }
            }
        }
    }

    private fun ensureShizukuUserServiceBoundAsync() {
        storageExecutor.execute {
            bindShizukuUserServiceIfNeeded()
        }
    }

    private fun bindShizukuUserServiceIfNeeded() {
        if (!RootFileAccess.hasShizukuPermission(this)) {
            return
        }
        synchronized(shizukuUserServiceLock) {
            shizukuUserService?.let { service ->
                if (service.asBinder()?.isBinderAlive == true) {
                    return
                }
            }
            if (shizukuUserServiceBinding) {
                return
            }
            shizukuUserServiceBinding = true
        }
        runCatching {
            Shizuku.bindUserService(shizukuUserServiceArgs, shizukuUserServiceConnection)
        }.onFailure { error ->
            synchronized(shizukuUserServiceLock) {
                shizukuUserServiceBinding = false
                shizukuUserServiceLock.notifyAll()
            }
            Log.w(TAG, "Failed to bind Shizuku UserService", error)
        }
    }

    private fun clearShizukuUserService() {
        synchronized(shizukuUserServiceLock) {
            shizukuUserService = null
            shizukuUserServiceBinding = false
            shizukuUserServiceLock.notifyAll()
        }
    }

    private fun handleShizukuPermissionRequest(result: MethodChannel.Result) {
        if (!RootFileAccess.isShizukuAvailable(this)) {
            result.success(false)
            return
        }
        if (RootFileAccess.hasShizukuPermission(this)) {
            ensureShizukuUserServiceBoundAsync()
            result.success(true)
            return
        }
        if (pendingShizukuPermissionResult != null) {
            result.error("busy", "shizuku permission request already in progress", null)
            return
        }
        pendingShizukuPermissionResult = result
        runCatching { Shizuku.requestPermission(REQUEST_CODE_SHIZUKU) }
            .onFailure {
                pendingShizukuPermissionResult = null
                result.error(
                    "shizuku_request_failed",
                    it.message ?: "failed to request shizuku permission",
                    null,
                )
            }
    }

    private fun hasManageAllFilesAccess(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.R || Environment.isExternalStorageManager()

    private fun openManageAllFilesAccessSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val appIntent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
            data = Uri.parse("package:$packageName")
        }
        runCatching { startActivity(appIntent) }
            .onFailure { startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)) }
    }

    private fun openShizukuApp() {
        val launchIntent =
            packageManager.getLaunchIntentForPackage("moe.shizuku.privileged.api")
                ?: packageManager.getLaunchIntentForPackage("moe.shizuku.manager")
        if (launchIntent != null) {
            startActivity(launchIntent)
            return
        }
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:moe.shizuku.privileged.api")
            },
        )
    }

    companion object {
        private const val TAG = "FlSQLiteViewer"
        private const val STORAGE_ACCESS_CHANNEL = "lingxue.flsqliteviewer/storage_access"
        private const val REQUEST_CODE_SHIZUKU = 52001
        private const val SHIZUKU_USER_SERVICE_BIND_TIMEOUT_MS = 4_000L
    }
}