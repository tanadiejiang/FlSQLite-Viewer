import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/database_models.dart';

/// Abstract file access operations - works on both Android and Windows.
/// On Android, privileged modes (Root/Shizuku) are handled via platform channels.
abstract class DatabaseFileAccess {
  /// Copy source DB (and its WAL/SHM sidecars if present) to a working copy.
  /// Returns the path to the working copy.
  Future<String> copyToWorkDir(String sourcePath);

  /// Write the working copy back to the original source path.
  Future<void> writeBackToSource(String workPath, String sourcePath,
      {FileAccessMode mode = FileAccessMode.normal});

  /// List directory entries at [dirPath].
  Future<List<DirectoryEntry>> listDirectory(String dirPath,
      {FileAccessMode mode = FileAccessMode.normal});

  /// Check whether a file exists at [filePath].
  Future<bool> fileExists(String filePath,
      {FileAccessMode mode = FileAccessMode.normal});

  /// Read file bytes at [filePath].
  Future<List<int>> readFile(String filePath,
      {FileAccessMode mode = FileAccessMode.normal});

  /// Write [bytes] to [filePath].
  Future<void> writeFile(String filePath, List<int> bytes,
      {FileAccessMode mode = FileAccessMode.normal});

  /// Get the working directory for storing temporary DB copies.
  Future<Directory> getWorkDir();
}

/// Normal (non-privileged) file access implementation.
class NormalFileAccess implements DatabaseFileAccess {
  @override
  Future<String> copyToWorkDir(String sourcePath) async {
    final workDir = await getWorkDir();
    final name = p.basename(sourcePath);
    final workPath = p.join(workDir.path, name);
    await File(sourcePath).copy(workPath);
    // Copy WAL/SHM if they exist
    final walPath = '$sourcePath-wal';
    final shmPath = '$sourcePath-shm';
    if (await File(walPath).exists()) {
      await File(walPath).copy('$workPath-wal');
    }
    if (await File(shmPath).exists()) {
      await File(shmPath).copy('$workPath-shm');
    }
    return workPath;
  }

  @override
  Future<void> writeBackToSource(String workPath, String sourcePath,
      {FileAccessMode mode = FileAccessMode.normal}) async {
    await File(workPath).copy(sourcePath);
    // Copy back WAL/SHM
    final walPath = '$workPath-wal';
    final shmPath = '$workPath-shm';
    if (await File(walPath).exists()) {
      await File(walPath).copy('$sourcePath-wal');
    }
    if (await File(shmPath).exists()) {
      await File(shmPath).copy('$sourcePath-shm');
    }
  }

  @override
  Future<List<DirectoryEntry>> listDirectory(String dirPath,
      {FileAccessMode mode = FileAccessMode.normal}) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      throw FileSystemException('Directory does not exist or is inaccessible', dirPath);
    }
    final entries = <DirectoryEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      entries.add(DirectoryEntry(
        name: p.basename(entity.path),
        isDirectory: entity is Directory,
        fullPath: entity.path,
      ));
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  @override
  Future<bool> fileExists(String filePath,
      {FileAccessMode mode = FileAccessMode.normal}) async {
    return File(filePath).exists();
  }

  @override
  Future<List<int>> readFile(String filePath,
      {FileAccessMode mode = FileAccessMode.normal}) async {
    return File(filePath).readAsBytes();
  }

  @override
  Future<void> writeFile(String filePath, List<int> bytes,
      {FileAccessMode mode = FileAccessMode.normal}) async {
    await File(filePath).writeAsBytes(bytes);
  }

  @override
  Future<Directory> getWorkDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final workDir = Directory(p.join(appDir.path, 'db_workspace'));
    if (!await workDir.exists()) {
      await workDir.create(recursive: true);
    }
    return workDir;
  }
}