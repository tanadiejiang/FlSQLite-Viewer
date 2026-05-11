package lingxue.flsqliteviewer

import android.content.Context
import android.content.pm.PackageManager
import rikka.shizuku.Shizuku
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit

data class ProcessTextResult(val exitCode: Int, val stdout: String, val stderr: String)
data class ProcessBytesResult(val exitCode: Int, val stdout: ByteArray, val stderr: String)

object RootFileAccess {
    var cachedRootAccess: Boolean? = null
    var cachedRootAccessAt: Long = 0L
    var cachedShizukuPermission: Boolean? = null
    var cachedShizukuPermissionAt: Long = 0L

    private const val ACCESS_CACHE_MS = 5000L
    private const val ACCESS_CHECK_TIMEOUT_MS = 8000L
    private const val DIRECTORY_LIST_TIMEOUT_MS = 45000L
    private const val FILE_IO_TIMEOUT_MS = 30000L

    fun isShizukuInstalled(context: Context): Boolean =
        runCatching { context.packageManager.getPackageInfo("moe.shizuku.privileged.api", 0); true }
            .getOrDefault(
                runCatching { context.packageManager.getPackageInfo("moe.shizuku.manager", 0); true }
                    .getOrDefault(false),
            )

    fun isShizukuAvailable(context: Context): Boolean =
        runCatching { Shizuku.getBinder()?.isBinderAlive == true || Shizuku.pingBinder() }.getOrDefault(false)

    fun hasShizukuPermission(context: Context, forceRefresh: Boolean = false): Boolean {
        val now = System.currentTimeMillis()
        if (!forceRefresh) {
            cachedShizukuPermission?.let { if (now - cachedShizukuPermissionAt < ACCESS_CACHE_MS) return it }
        }
        val granted = isShizukuAvailable(context) &&
            runCatching { Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED }
                .getOrDefault(false)
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
            val result = executeTextProcess(
                executor,
                Runtime.getRuntime().exec(arrayOf("su", "-c", "id")),
                ACCESS_CHECK_TIMEOUT_MS,
                "root access check",
            )
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

    internal fun executeTextProcess(
        executor: ExecutorService,
        process: Process,
        timeoutMs: Long,
        operation: String = "process",
    ): ProcessTextResult {
        val deadlineNanos = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
        val stdout = executor.submit<String> { process.inputStream.bufferedReader().use { it.readText() } }
        val stderr = executor.submit<String> { process.errorStream.bufferedReader().use { it.readText().trim() } }
        val waitResult = executor.submit<Int> { process.waitFor() }

        fun remainingMs(minimumMs: Long = 1000L): Long {
            val remaining = TimeUnit.NANOSECONDS.toMillis(deadlineNanos - System.nanoTime())
            return maxOf(minimumMs, remaining)
        }

        return try {
            val exitCode = waitResult.get(timeoutMs, TimeUnit.MILLISECONDS)
            ProcessTextResult(
                exitCode,
                stdout.get(remainingMs(), TimeUnit.MILLISECONDS),
                stderr.get(remainingMs(), TimeUnit.MILLISECONDS),
            )
        } catch (e: Exception) {
            process.destroyForcibly()
            waitResult.cancel(true)
            stdout.cancel(true)
            stderr.cancel(true)
            if (e is java.util.concurrent.TimeoutException) {
                throw IllegalStateException("$operation timeout after ${timeoutMs}ms", e)
            }
            throw e
        }
    }

    internal fun executeBytesProcess(
        executor: ExecutorService,
        process: Process,
        timeoutMs: Long,
        operation: String = "process",
    ): ProcessBytesResult {
        val deadlineNanos = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
        val stdout = executor.submit<ByteArray> { process.inputStream.use { it.readBytes() } }
        val stderr = executor.submit<String> { process.errorStream.bufferedReader().use { it.readText().trim() } }
        val waitResult = executor.submit<Int> { process.waitFor() }

        fun remainingMs(minimumMs: Long = 1000L): Long {
            val remaining = TimeUnit.NANOSECONDS.toMillis(deadlineNanos - System.nanoTime())
            return maxOf(minimumMs, remaining)
        }

        return try {
            val exitCode = waitResult.get(timeoutMs, TimeUnit.MILLISECONDS)
            ProcessBytesResult(
                exitCode,
                stdout.get(remainingMs(), TimeUnit.MILLISECONDS),
                stderr.get(remainingMs(), TimeUnit.MILLISECONDS),
            )
        } catch (e: Exception) {
            process.destroyForcibly()
            waitResult.cancel(true)
            stdout.cancel(true)
            stderr.cancel(true)
            if (e is java.util.concurrent.TimeoutException) {
                throw IllegalStateException("$operation timeout after ${timeoutMs}ms", e)
            }
            throw e
        }
    }

    internal fun executeBinaryWriteProcess(
        executor: ExecutorService,
        process: Process,
        bytes: ByteArray,
        timeoutMs: Long,
        operation: String = "process",
    ): ProcessTextResult {
        val deadlineNanos = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
        val writer = executor.submit<Unit> { process.outputStream.use { it.write(bytes); it.flush() } }
        val stdout = executor.submit<String> { process.inputStream.bufferedReader().use { it.readText() } }
        val stderr = executor.submit<String> { process.errorStream.bufferedReader().use { it.readText().trim() } }
        val waitResult = executor.submit<Int> { process.waitFor() }

        fun remainingMs(minimumMs: Long = 1000L): Long {
            val remaining = TimeUnit.NANOSECONDS.toMillis(deadlineNanos - System.nanoTime())
            return maxOf(minimumMs, remaining)
        }

        return try {
            writer.get(timeoutMs, TimeUnit.MILLISECONDS)
            val exitCode = waitResult.get(remainingMs(), TimeUnit.MILLISECONDS)
            ProcessTextResult(
                exitCode,
                stdout.get(remainingMs(), TimeUnit.MILLISECONDS),
                stderr.get(remainingMs(), TimeUnit.MILLISECONDS),
            )
        } catch (e: Exception) {
            process.destroyForcibly()
            writer.cancel(true)
            waitResult.cancel(true)
            stdout.cancel(true)
            stderr.cancel(true)
            if (e is java.util.concurrent.TimeoutException) {
                throw IllegalStateException("$operation timeout after ${timeoutMs}ms", e)
            }
            throw e
        }
    }

    internal fun shellEscape(value: String): String = "'" + value.replace("'", "'\"'\"'") + "'"

    internal fun exceptionDetail(error: Exception): String =
        error.message?.takeIf { it.isNotBlank() } ?: error.javaClass.simpleName

    internal fun candidatePaths(path: String): LinkedHashSet<String> {
        val normalized = path.trim().ifEmpty { "/" }
        val candidates = linkedSetOf(normalized)
        if (normalized == "/data/user/0") {
            candidates.add("/data/data")
            candidates.add("/data_mirror/data_ce/null/0")
        }
        if (normalized == "/data/data") {
            candidates.add("/data/user/0")
            candidates.add("/data_mirror/data_ce/null/0")
        }
        if (normalized == "/data_mirror/data_ce/null/0") {
            candidates.add("/data/user/0")
            candidates.add("/data/data")
        }
        if (normalized.startsWith("/data/user/0/")) {
            candidates.add(normalized.replaceFirst("/data/user/0/", "/data/data/"))
            candidates.add(normalized.replaceFirst("/data/user/0/", "/data_mirror/data_ce/null/0/"))
        }
        if (normalized.startsWith("/data/data/")) {
            candidates.add(normalized.replaceFirst("/data/data/", "/data/user/0/"))
            candidates.add(normalized.replaceFirst("/data/data/", "/data_mirror/data_ce/null/0/"))
        }
        if (normalized.startsWith("/data_mirror/data_ce/null/0/")) {
            candidates.add(normalized.replaceFirst("/data_mirror/data_ce/null/0/", "/data/user/0/"))
            candidates.add(normalized.replaceFirst("/data_mirror/data_ce/null/0/", "/data/data/"))
        }
        if (normalized == "/storage/emulated/0") candidates.add("/sdcard")
        if (normalized == "/sdcard") candidates.add("/storage/emulated/0")
        if (normalized.startsWith("/storage/emulated/0/")) {
            candidates.add(normalized.replaceFirst("/storage/emulated/0/", "/sdcard/"))
        }
        if (normalized.startsWith("/sdcard/")) {
            candidates.add(normalized.replaceFirst("/sdcard/", "/storage/emulated/0/"))
        }
        return candidates
    }

    internal fun parentPath(path: String): String {
        val normalized = path.trim().replace('\\', '/')
        val idx = normalized.lastIndexOf('/')
        return if (idx <= 0) "/" else normalized.substring(0, idx)
    }

    private fun directoryListCommand(candidate: String): String =
        """
        target=${shellEscape(candidate)}
        if [ ! -e "${'$'}target" ]; then
          echo __FLSQL_NODIR__ 1>&2
          exit 2
        fi
        if [ ! -d "${'$'}target" ]; then
          echo __FLSQL_NOTDIR__ 1>&2
          exit 3
        fi
        cd "${'$'}target" || {
          echo __FLSQL_CD_FAILED__ 1>&2
          exit 4
        }

        list_with_ls() {
          LC_ALL=C ls -1A 2>/dev/null | while IFS= read -r name; do
            [ -n "${'$'}name" ] || continue
            [ "${'$'}name" = "." ] && continue
            [ "${'$'}name" = ".." ] && continue
            if [ -d "${'$'}name" ]; then
              kind=directory
            elif [ -f "${'$'}name" ]; then
              kind=file
            else
              kind=other
            fi
            printf '%s\t%s\n' "${'$'}kind" "${'$'}name"
          done
        }

        list_with_find() {
          find . -mindepth 1 -maxdepth 1 2>/dev/null | while IFS= read -r item; do
            [ -n "${'$'}item" ] || continue
            name=${'$'}{item#./}
            [ -n "${'$'}name" ] || continue
            if [ -d "${'$'}item" ]; then
              kind=directory
            elif [ -f "${'$'}item" ]; then
              kind=file
            else
              kind=other
            fi
            printf '%s\t%s\n' "${'$'}kind" "${'$'}name"
          done
        }

        output=${'$'}(list_with_ls)
        status=${'$'}?
        if [ ${'$'}status -eq 0 ] && [ -n "${'$'}output" ]; then
          printf '%s\n' "${'$'}output"
          exit 0
        fi

        output=${'$'}(list_with_find)
        status=${'$'}?
        if [ ${'$'}status -eq 0 ]; then
          printf '%s\n' "${'$'}output"
          exit 0
        fi

        echo __FLSQL_LIST_FAILED__ 1>&2
        exit 5
        """.trimIndent()

    internal fun fileListAdapter(
        executor: ExecutorService,
        path: String,
        startProcess: (String) -> Process,
    ): List<Map<String, String>> {
        val candidates = candidatePaths(path).toList()
        val errors = mutableListOf<String>()
        for (candidate in candidates) {
            val result = try {
                executeTextProcess(
                    executor,
                    startProcess(directoryListCommand(candidate)),
                    DIRECTORY_LIST_TIMEOUT_MS,
                    "directory listing for $candidate",
                )
            } catch (error: Exception) {
                errors.add("$candidate: ${exceptionDetail(error)}")
                continue
            }
            if (result.exitCode == 0) {
                return result.stdout.lineSequence()
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
                    }
                    .distinctBy { "${it["type"]}\u0000${it["name"]}" }
                    .sortedWith(
                        compareBy<Map<String, String>> { it["type"] != "directory" }
                            .thenBy { it["name"]?.lowercase() },
                    )
                    .toList()
            }
            val detail = when {
                result.stderr.contains("__FLSQL_NODIR__") -> "dir not found"
                result.stderr.contains("__FLSQL_NOTDIR__") -> "not a directory"
                result.stderr.contains("__FLSQL_CD_FAILED__") -> "cd failed"
                result.stderr.contains("__FLSQL_LIST_FAILED__") -> "list command failed"
                result.stderr.isNotBlank() -> "exit=${result.exitCode} err=${result.stderr}"
                else -> "exit=${result.exitCode}"
            }
            errors.add("$candidate: $detail")
        }
        throw IllegalStateException("directory listing failed — candidates: ${errors.joinToString("; ")}")
    }

    internal fun fileReadAdapter(
        executor: ExecutorService,
        path: String,
        startProcess: (String) -> Process,
    ): ByteArray {
        val candidates = candidatePaths(path).toList()
        val errors = mutableListOf<String>()
        for (candidate in candidates) {
            val command =
                "if [ -f ${shellEscape(candidate)} ]; then cat ${shellEscape(candidate)}; else echo __FLSQL_NOFILE__ 1>&2; exit 2; fi"
            val result = try {
                executeBytesProcess(
                    executor,
                    startProcess(command),
                    FILE_IO_TIMEOUT_MS,
                    "file read for $candidate",
                )
            } catch (error: Exception) {
                errors.add("$candidate: ${exceptionDetail(error)}")
                continue
            }
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
        executor: ExecutorService,
        path: String,
        startProcess: (String) -> Process,
    ): Boolean {
        for (candidate in candidatePaths(path)) {
            val result = try {
                executeTextProcess(
                    executor,
                    startProcess("[ -e ${shellEscape(candidate)} ]"),
                    FILE_IO_TIMEOUT_MS,
                    "exists check for $candidate",
                )
            } catch (_: Exception) {
                continue
            }
            if (result.exitCode == 0) return true
        }
        return false
    }

    internal fun fileWriteAdapter(
        executor: ExecutorService,
        path: String,
        bytes: ByteArray,
        startProcess: (String) -> Process,
    ) {
        val candidates = candidatePaths(path).toList()
        val errors = mutableListOf<String>()
        for (candidate in candidates) {
            val targetParent = parentPath(candidate)
            val tempPath = "$candidate.__flsql_tmp__"
            val command =
                "mkdir -p ${shellEscape(targetParent)} && tmp=${shellEscape(tempPath)} && cat > \"\$tmp\" && mv \"\$tmp\" ${shellEscape(candidate)}"
            val result = try {
                executeBinaryWriteProcess(
                    executor,
                    startProcess(command),
                    bytes,
                    FILE_IO_TIMEOUT_MS,
                    "file write for $candidate",
                )
            } catch (error: Exception) {
                errors.add("$candidate: ${exceptionDetail(error)}")
                continue
            }
            if (result.exitCode == 0) return
            val detail =
                if (result.stderr.isNotBlank()) "exit=${result.exitCode} err=${result.stderr}" else "exit=${result.exitCode}"
            errors.add("$candidate: $detail")
        }
        throw IllegalStateException("file write failed — candidates: ${errors.joinToString("; ")}")
    }
}