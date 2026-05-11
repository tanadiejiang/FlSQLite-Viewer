

import 'package:flutter/services.dart';

import '../../models/database_models.dart';
import 'database_file_access.dart';

const _channel = MethodChannel('lingxue.flsqliteviewer/storage_access');

/// Android privileged file access via platform channel (Root / Shizuku / ManageAllFiles).
class AndroidSpecialFileAccess extends NormalFileAccess {
  @override
  Future<List<DirectoryEntry>> listDirectory(String dirPath,
      {FileAccessMode mode = FileAccessMode.normal}) async {
    if (mode == FileAccessMode.root) {
      final result = await _channel.invokeListMethod<Map>(
          'listDirectoryEntriesWithRoot', {'path': dirPath});
      return _parseDirectoryEntries(result);
    }
    if (mode == FileAccessMode.shizuku) {
      final result = await _channel.invokeListMethod<Map>(
          'listDirectoryEntriesWithShizuku', {'path': dirPath});
      return _parseDirectoryEntries(result);
    }
    return super.listDirectory(dirPath, mode: mode);
  }

  @override
  Future<bool> fileExists(String filePath,
      {FileAccessMode mode = FileAccessMode.normal}) async {
    if (mode == FileAccessMode.root) {
      return await _channel
              .invokeMethod<bool>('existsWithRoot', {'path': filePath}) ??
          false;
    }
    if (mode == FileAccessMode.shizuku) {
      return await _channel
              .invokeMethod<bool>('existsWithShizuku', {'path': filePath}) ??
          false;
    }
    return super.fileExists(filePath, mode: mode);
  }

  @override
  Future<List<int>> readFile(String filePath,
      {FileAccessMode mode = FileAccessMode.normal}) async {
    if (mode == FileAccessMode.root) {
      final bytes =
          await _channel.invokeMethod('readFileWithRoot', {'path': filePath});
      return (bytes as Uint8List).toList();
    }
    if (mode == FileAccessMode.shizuku) {
      final bytes = await _channel
          .invokeMethod('readFileWithShizuku', {'path': filePath});
      return (bytes as Uint8List).toList();
    }
    return super.readFile(filePath, mode: mode);
  }

  @override
  Future<void> writeFile(String filePath, List<int> bytes,
      {FileAccessMode mode = FileAccessMode.normal}) async {
    if (mode == FileAccessMode.root) {
      await _channel.invokeMethod(
          'writeFileWithRoot', {'path': filePath, 'bytes': Uint8List.fromList(bytes)});
      return;
    }
    if (mode == FileAccessMode.shizuku) {
      await _channel.invokeMethod(
          'writeFileWithShizuku', {'path': filePath, 'bytes': Uint8List.fromList(bytes)});
      return;
    }
    return super.writeFile(filePath, bytes, mode: mode);
  }

  @override
  Future<void> writeBackToSource(String workPath, String sourcePath,
      {FileAccessMode mode = FileAccessMode.normal}) async {
    final bytes = await super.readFile(workPath);
    await writeFile(sourcePath, bytes, mode: mode);
    // Also write back WAL/SHM
    await _copySidecar(workPath, sourcePath, 'wal', mode: mode);
    await _copySidecar(workPath, sourcePath, 'shm', mode: mode);
  }

  Future<void> _copySidecar(String workPath, String sourcePath, String ext,
      {FileAccessMode mode = FileAccessMode.normal}) async {
    try {
      final sidecarPath = '$workPath-$ext';
      if (await super.fileExists(sidecarPath)) {
        final sidecarBytes = await super.readFile(sidecarPath);
        await writeFile('$sourcePath-$ext', sidecarBytes, mode: mode);
      }
    } catch (_) {
      // sidecar may not exist, ignore
    }
  }

  List<DirectoryEntry> _parseDirectoryEntries(List<Map>? result) {
    if (result == null) return [];
    return result.map((e) {
      return DirectoryEntry(
        name: e['name'] as String,
        isDirectory: e['type'] == 'directory',
        fullPath: '', // filled by caller
      );
    }).toList();
  }

  /// Copy file via privileged access from source to work dir.
  Future<String> copyToWorkDirPrivileged(String sourcePath,
      {required FileAccessMode mode}) async {
    final workDir = await getWorkDir();
    final name = sourcePath.split('/').last;
    final workPath = '${workDir.path}/$name';
    final bytes = await readFile(sourcePath, mode: mode);
    await writeFile(workPath, bytes, mode: FileAccessMode.normal);
    // Try to copy WAL/SHM too
    try {
      if (await fileExists('$sourcePath-wal', mode: mode)) {
        final walBytes = await readFile('$sourcePath-wal', mode: mode);
        await writeFile('$workPath-wal', walBytes);
      }
      if (await fileExists('$sourcePath-shm', mode: mode)) {
        final shmBytes = await readFile('$sourcePath-shm', mode: mode);
        await writeFile('$workPath-shm', shmBytes);
      }
    } catch (_) {}
    return workPath;
  }

  // --- Authorization status queries ---

  Future<bool> hasManageAllFilesAccess() async {
    return await _channel.invokeMethod<bool>('hasManageAllFilesAccess') ??
        false;
  }

  Future<void> openManageAllFilesAccessSettings() async {
    await _channel.invokeMethod('openManageAllFilesAccessSettings');
  }

  Future<bool> hasRootAccess({bool forceRefresh = false}) async {
    return await _channel.invokeMethod<bool>(
            'hasRootAccess', {'forceRefresh': forceRefresh}) ??
        false;
  }

  Future<bool> hasShizukuPermission({bool forceRefresh = false}) async {
    return await _channel.invokeMethod<bool>(
            'hasShizukuPermission', {'forceRefresh': forceRefresh}) ??
        false;
  }

  Future<Map<String, dynamic>> getShizukuStatus(
      {bool forceRefresh = false}) async {
    final result = await _channel.invokeMethod<Map>(
        'getShizukuStatus', {'forceRefresh': forceRefresh});
    return Map<String, dynamic>.from(result ?? {});
  }

  Future<bool> isShizukuAvailable() async {
    return await _channel.invokeMethod<bool>('isShizukuAvailable') ?? false;
  }

  Future<void> openShizukuApp() async {
    await _channel.invokeMethod('openShizukuApp');
  }

  Future<bool> requestShizukuPermission() async {
    return await _channel.invokeMethod<bool>('requestShizukuPermission') ??
        false;
  }
}