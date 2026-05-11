package lingxue.flsqliteviewer.fileaccess

import android.content.Context
import rikka.shizuku.Shizuku
import java.util.concurrent.ExecutorService

object ShizukuFileAccess {

    fun listDirectoryEntries(context: Context, executor: ExecutorService, path: String): List<Map<String, String>> {
        if (!lingxue.flsqliteviewer.RootFileAccess.hasShizukuPermission(context)) {
            throw IllegalStateException("Shizuku permission not granted")
        }
        return lingxue.flsqliteviewer.RootFileAccess.run {
            fileListAdapter(executor, path) { command ->
                newShizukuProcess(arrayOf("sh", "-c", command), null, null)
            }
        }
    }

    fun readFile(context: Context, executor: ExecutorService, path: String): ByteArray {
        if (!lingxue.flsqliteviewer.RootFileAccess.hasShizukuPermission(context)) {
            throw IllegalStateException("Shizuku permission not granted")
        }
        return lingxue.flsqliteviewer.RootFileAccess.run {
            fileReadAdapter(executor, path) { command ->
                newShizukuProcess(arrayOf("sh", "-c", command), null, null)
            }
        }
    }

    fun writeFile(context: Context, executor: ExecutorService, path: String, bytes: ByteArray) {
        if (!lingxue.flsqliteviewer.RootFileAccess.hasShizukuPermission(context)) {
            throw IllegalStateException("Shizuku permission not granted")
        }
        lingxue.flsqliteviewer.RootFileAccess.run {
            fileWriteAdapter(executor, path, bytes) { command ->
                newShizukuProcess(arrayOf("sh", "-c", command), null, null)
            }
        }
    }

    fun exists(context: Context, executor: ExecutorService, path: String): Boolean {
        if (!lingxue.flsqliteviewer.RootFileAccess.hasShizukuPermission(context)) {
            return false
        }
        return lingxue.flsqliteviewer.RootFileAccess.run {
            fileExistsAdapter(executor, path) { command ->
                newShizukuProcess(arrayOf("sh", "-c", command), null, null)
            }
        }
    }

    private fun newShizukuProcess(
        command: Array<String>,
        environment: Array<String>?,
        workingDirectory: String?,
    ): Process {
        return try {
            val method = Shizuku::class.java.getDeclaredMethod(
                "newProcess",
                Array<String>::class.java,
                Array<String>::class.java,
                String::class.java,
            )
            method.isAccessible = true
            method.invoke(null, command, environment, workingDirectory) as Process
        } catch (e: java.lang.reflect.InvocationTargetException) {
            throw IllegalStateException(
                "Shizuku newProcess failed: ${e.cause?.message ?: e.cause}",
                e.cause ?: e,
            )
        } catch (e: Exception) {
            throw IllegalStateException("Shizuku newProcess error: ${e.message}", e)
        }
    }
}