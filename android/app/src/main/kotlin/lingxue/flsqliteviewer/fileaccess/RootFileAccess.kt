package lingxue.flsqliteviewer

import android.content.Context
import android.content.pm.PackageManager
import android.os.Process as AndroidProcess
import rikka.shizuku.Shizuku
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit

data class ProcessTextResult(val exitCode: Int, val stdout: String, val stderr: String)
data class ProcessBytesResult(val exitCode: Int, val stdout: ByteArray, val stderr: String)

object RootFileAccess {
    var cachedRootAccess: Boolean? = null
    var cachedRootAccessAt: Long = 0L
    var cachedShizukuPermission: Boolean? = null
    var cachedShizukuPermissionAt: Long = 0L

    private val ACCESS_CACHE_MS = 5000L
    private val PROCESS_TIMEOUT_MS = 8000L

    fun isShizukuInstalled(context: Context): Boolean =
        runCatching { context.packageManager.getPackageInfo("moe.shizuku.privileged.api", 0); true }
            .getOrDefault(runCatching { context.packageManager.getPackageInfo("moe.shizuku.manager", 0); true }
                .getOrDefault(false))

    fun isShizukuAvailable(context: Context): Boolean =
        runCatching { Shizuku.getBinder()?.isBinderAlive == true || Shizuku.pingBinder() }.getOrDefault(false)

    fun hasShizukuPermission(context: Context, forceRefresh: Boolean = false): Boolean {
        val now = System.currentTimeMillis()
        if (!forceRefresh) {
            cachedShizukuPermission?.let { if (now - cachedShizukuPermissionAt < ACCESS_CACHE_MS) return it }
        }
        val granted = isShizukuAvailable(context) &&
                runCatching { Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED }.getOrDefault(false)
        cachedShizukuPermission = granted
        cachedShizukuPermissionAt = now
        return granted
    }

    fun hasRootAccess(executor: ExecutorService, forceRefresh: Boolean = false): Boolean {
        val now = System.currentTimeMillis()
        if (!forceRefresh) {
            cachedRootAccess?.let { if (now - cachedRootAccessAt < ACCESS_CACHE_MS) return it }
        }
        val granted = runCatching {
            val result = executeTextProcess(executor, Runtime.getRuntime().exec(arrayOf("su", "-c", "id")), PROCESS_TIMEOUT_MS)
            result.exitCode == 0 && (result.stdout + result.stderr).lowercase().contains("uid=0")
        }.getOrDefault(false)
        cachedRootAccess = granted
        cachedRootAccessAt = now
        return granted
    }

    private fun rootProcess(command: String): Process =
        Runtime.getRuntime().exec(arrayOf("su", "-c", command))

    fun listDirectoryEntries(executor: ExecutorService, path: String): List<Map<String, String>> =
        fileListAdapter(executor, path) { command -> rootProcess(command) }

    fun readFile(executor: ExecutorService, path: String): ByteArray =
        fileReadAdapter(executor, path) { command -> rootProcess(command) }

    fun writeFile(executor: ExecutorService, path: String, bytes: ByteArray) {
        fileWriteAdapter(executor, path, bytes) { command -> rootProcess(command) }
    }

    fun exists(executor: ExecutorService, path: String): Boolean =
        fileExistsAdapter(executor, path) { command -> rootProcess(command) }

    // Shared helpers

    internal fun executeTextProcess(executor: ExecutorService, process: Process, timeoutMs: Long): ProcessTextResult {
        val stdout = executor.submit<String> { process.inputStream.bufferedReader().use { it.readText() } }
        val stderr = executor.submit<String> { process.errorStream.bufferedReader().use { it.readText().trim() } }
        val waitResult = executor.submit<Int> { process.waitFor() }
        return try {
            ProcessTextResult(waitResult.get(timeoutMs, TimeUnit.MILLISECONDS),
                stdout.get(1, TimeUnit.SECONDS), stderr.get(1, TimeUnit.SECONDS))
        } catch (e: Exception) {
            process.destroyForcibly(); waitResult.cancel(true); stdout.cancel(true); stderr.cancel(true); throw e
        }
    }

    internal fun executeBytesProcess(executor: ExecutorService, process: Process, timeoutMs: Long): ProcessBytesResult {
        val stdout = executor.submit<ByteArray> { process.inputStream.use { it.readBytes() } }
        val stderr = executor.submit<String> { process.errorStream.bufferedReader().use { it.readText().trim() } }
        val waitResult = executor.submit<Int> { process.waitFor() }
        return try {
            ProcessBytesResult(waitResult.get(timeoutMs, TimeUnit.MILLISECONDS),
                stdout.get(1, TimeUnit.SECONDS), stderr.get(1, TimeUnit.SECONDS))
        } catch (e: Exception) {
            process.destroyForcibly(); waitResult.cancel(true); stdout.cancel(true); stderr.cancel(true); throw e
        }
    }

    internal fun executeBinaryWriteProcess(executor: ExecutorService, process: Process, bytes: ByteArray, timeoutMs: Long): ProcessTextResult {
        val writer = executor.submit<Unit> { process.outputStream.use { it.write(bytes); it.flush() } }
        val stdout = executor.submit<String> { process.inputStream.bufferedReader().use { it.readText() } }
        val stderr = executor.submit<String> { process.errorStream.bufferedReader().use { it.readText().trim() } }
        val waitResult = executor.submit<Int> { process.waitFor() }
        return try {
            writer.get(timeoutMs, TimeUnit.MILLISECONDS)
            ProcessTextResult(waitResult.get(timeoutMs, TimeUnit.MILLISECONDS),
                stdout.get(1, TimeUnit.SECONDS), stderr.get(1, TimeUnit.SECONDS))
        } catch (e: Exception) {
            process.destroyForcibly(); writer.cancel(true); waitResult.cancel(true); stdout.cancel(true); stderr.cancel(true); throw e
        }
    }

    internal fun shellEscape(value: String): String = "'" + value.replace("'", "'\"'\"'") + "'"

    internal fun candidatePaths(path: String): LinkedHashSet<String> {
        val normalized = path.trim().ifEmpty { "/" }
        val candidates = linkedSetOf(normalized)
        if (normalized == "/data/user/0") candidates.add("/data/data")
        if (normalized == "/data/data") candidates.add("/data/user/0")
        if (normalized.startsWith("/data/user/0/")) candidates.add(normalized.replaceFirst("/data/user/0/", "/data/data/"))
        if (normalized.startsWith("/data/data/")) candidates.add(normalized.replaceFirst("/data/data/", "/data/user/0/"))
        if (normalized == "/storage/emulated/0") candidates.add("/sdcard")
        if (normalized == "/sdcard") candidates.add("/storage/emulated/0")
        if (normalized.startsWith("/storage/emulated/0/")) candidates.add(normalized.replaceFirst("/storage/emulated/0/", "/sdcard/"))
        if (normalized.startsWith("/sdcard/")) candidates.add(normalized.replaceFirst("/sdcard/", "/storage/emulated/0/"))
        return candidates
    }

    internal fun parentPath(path: String): String {
        val normalized = path.trim().replace('\\', '/')
        val idx = normalized.lastIndexOf('/')
        return if (idx <= 0) "/" else normalized.substring(0, idx)
    }

    internal fun fileListAdapter(
        executor: ExecutorService, path: String, startProcess: (String) -> Process
    ): List<Map<String, String>> {
        val candidates = candidatePaths(path).toList()
        val errors = mutableListOf<String>()
        for (candidate in candidates) {
            val command = """
                if [ -d ${shellEscape(candidate)} ]; then
                  cd ${shellEscape(candidate)} || exit 2
                  for e in ./* ./.[!.]* ./..?*; do
                    [ -e "${'$'}e" ] || continue
                    name=${'$'}{e#./}
                    if [ -d "${'$'}e" ]; then
                      printf 'd\t%s\n' "${'$'}name"
                    elif [ -f "${'$'}e" ]; then
                      printf 'f\t%s\n' "${'$'}name"
                    fi
                  done
                else
                  echo __FLSQL_NODIR__ 1>&2
                  exit 2
                fi
            """.trimIndent()
            val result = executeTextProcess(executor, startProcess(command), PROCESS_TIMEOUT_MS)
            if (result.exitCode == 0) {
                return result.stdout.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.mapNotNull { line ->
                    val idx = line.indexOf('\t')
                    if (idx <= 0 || idx == line.length - 1) null
                    else {
                        val type = if (line.substring(0, idx) == "d") "directory" else "file"
                        val name = line.substring(idx + 1).trim()
                        if (name.isEmpty() || name == "." || name == "..") null
                        else mapOf("type" to type, "name" to name)
                    }
                }.distinctBy { "${it["type"]}\u0000${it["name"]}" }
                    .sortedWith(compareBy<Map<String, String>> { it["type"] != "directory" }.thenBy { it["name"]?.lowercase() })
                    .toList()
            }
            val detail = when {
                result.stderr.contains("__FLSQL_NODIR__") -> "dir not found"
                result.stderr.isNotBlank() -> "exit=${result.exitCode} err=${result.stderr}"
                else -> "exit=${result.exitCode}"
            }
            errors.add("$candidate: $detail")
        }
        throw IllegalStateException("directory listing failed — candidates: ${errors.joinToString("; ")}")
    }

    internal fun fileReadAdapter(
        executor: ExecutorService, path: String, startProcess: (String) -> Process
    ): ByteArray {
        val candidates = candidatePaths(path).toList()
        val errors = mutableListOf<String>()
        for (candidate in candidates) {
            val command = "if [ -f ${shellEscape(candidate)} ]; then cat ${shellEscape(candidate)}; else echo __FLSQL_NOFILE__ 1>&2; exit 2; fi"
            val result = executeBytesProcess(executor, startProcess(command), PROCESS_TIMEOUT_MS)
            if (result.exitCode == 0) return result.stdout
            val detail = when {
                result.stderr.contains("__FLSQL_NOFILE__") -> "file not found"
                result.stderr.isNotBlank() -> "exit=${result.exitCode} err=${result.stderr}"
                else -> "exit=${result.exitCode}"
            }
            errors.add("$candidate: $detail")
        }
        throw IllegalStateException("file read failed — candidates: ${errors.joinToString("; ")}")
    }

    internal fun fileExistsAdapter(
        executor: ExecutorService, path: String, startProcess: (String) -> Process
    ): Boolean {
        for (candidate in candidatePaths(path)) {
            val result = executeTextProcess(executor, startProcess("[ -e ${shellEscape(candidate)} ]"), PROCESS_TIMEOUT_MS)
            if (result.exitCode == 0) return true
        }
        return false
    }

    internal fun fileWriteAdapter(
        executor: ExecutorService, path: String, bytes: ByteArray, startProcess: (String) -> Process
    ) {
        val candidates = candidatePaths(path).toList()
        val errors = mutableListOf<String>()
        for (candidate in candidates) {
            val targetParent = parentPath(candidate)
            val tempPath = "$candidate.__flsql_tmp__"
            val command = "mkdir -p ${shellEscape(targetParent)} && tmp=${shellEscape(tempPath)} && cat > \"\$tmp\" && mv \"\$tmp\" ${shellEscape(candidate)}"
            val result = executeBinaryWriteProcess(executor, startProcess(command), bytes, PROCESS_TIMEOUT_MS)
            if (result.exitCode == 0) return
            val detail = if (result.stderr.isNotBlank()) "exit=${result.exitCode} err=${result.stderr}" else "exit=${result.exitCode}"
            errors.add("$candidate: $detail")
        }
        throw IllegalStateException("file write failed — candidates: ${errors.joinToString("; ")}")
    }
}