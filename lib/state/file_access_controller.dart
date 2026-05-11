import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/file_session/android_special_file_access.dart';
import '../../core/file_session/database_file_access.dart';
import '../../models/database_models.dart';

/// Manages Android file access modes, permissions, and directory browsing state.
class FileAccessController extends ChangeNotifier {
  final AndroidSpecialFileAccess _access = AndroidSpecialFileAccess();
  final NormalFileAccess _normalAccess = NormalFileAccess();

  AndroidSpecialFileAccess get access => _access;
  NormalFileAccess get normalAccess => _normalAccess;

  bool _initialized = false;

  // --- State ---

  final Map<FileAccessMode, AccessCapability> capabilities = {
    FileAccessMode.manageAllFiles: const AccessCapability(
      mode: FileAccessMode.manageAllFiles,
      label: '全部文件访问',
      description: '允许访问外部存储中的任意文件',
    ),
    FileAccessMode.root: const AccessCapability(
      mode: FileAccessMode.root,
      label: 'Root 模式',
      description: '通过 su 访问受保护的路径',
    ),
    FileAccessMode.shizuku: const AccessCapability(
      mode: FileAccessMode.shizuku,
      label: 'Shizuku 模式',
      description: '通过 Shizuku 访问受限目录',
    ),
  };

  // --- Preferences ---

  /// Ensure saved access preferences are loaded at least once before any file
  /// operation. Safe to call multiple times — loads only on first invocation.
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await loadPreferences();
    _initialized = true;
  }

  Future<void> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final rootEnabled = prefs.getBool('root_mode_enabled') ?? false;
    final shizukuEnabled = prefs.getBool('shizuku_mode_enabled') ?? false;
    final allFilesEnabled = prefs.getBool('manage_all_files_enabled') ?? false;

    capabilities[FileAccessMode.root] =
        capabilities[FileAccessMode.root]!.copyWith(enabled: rootEnabled);
    capabilities[FileAccessMode.shizuku] = capabilities[FileAccessMode.shizuku]!
        .copyWith(enabled: shizukuEnabled);
    capabilities[FileAccessMode.manageAllFiles] = capabilities[
            FileAccessMode.manageAllFiles]!
        .copyWith(enabled: allFilesEnabled);
    notifyListeners();
  }

  Future<void> setCapabilityEnabled(FileAccessMode mode, bool enabled) async {
    capabilities[mode] = capabilities[mode]!.copyWith(enabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    switch (mode) {
      case FileAccessMode.root:
        await prefs.setBool('root_mode_enabled', enabled);
      case FileAccessMode.shizuku:
        await prefs.setBool('shizuku_mode_enabled', enabled);
      case FileAccessMode.manageAllFiles:
        await prefs.setBool('manage_all_files_enabled', enabled);
      default:
        break;
    }
    notifyListeners();
  }

  // --- Status checks ---

  Future<void> checkAllStatuses({bool forceRefresh = false}) async {
    // Mark all as checking
    for (final mode in capabilities.keys) {
      capabilities[mode] = capabilities[mode]!.copyWith(isChecking: true);
    }
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();

      // All files access — runtime grant, reflects real-time state
      final hasAllFiles = await _access.hasManageAllFilesAccess();
      capabilities[FileAccessMode.manageAllFiles] = capabilities[
              FileAccessMode.manageAllFiles]!
          .copyWith(
        enabled: hasAllFiles,
        statusText: hasAllFiles ? '已授权' : '未授权',
        isChecking: false,
      );
      await prefs.setBool('manage_all_files_enabled', hasAllFiles);

      // Root: auto-enable on success, but keep saved enabled on failure
      final hasRoot = await _access.hasRootAccess(forceRefresh: forceRefresh);
      final rootWasEnabled =
          prefs.getBool('root_mode_enabled') ?? false;
      if (hasRoot) {
        await prefs.setBool('root_mode_enabled', true);
      }
      capabilities[FileAccessMode.root] = capabilities[FileAccessMode.root]!
          .copyWith(
        enabled: hasRoot ? true : rootWasEnabled,
        statusText: hasRoot ? 'Root 可用' : 'Root 不可用',
        isChecking: false,
      );

      // Shizuku: auto-enable on granted, but keep saved enabled on failure
      final shizukuStatus =
          await _access.getShizukuStatus(forceRefresh: forceRefresh);
      final installed = shizukuStatus['installed'] == true;
      final running = shizukuStatus['running'] == true;
      final granted = shizukuStatus['permissionGranted'] == true;
      final shizukuWasEnabled =
          prefs.getBool('shizuku_mode_enabled') ?? false;
      String? statusText;
      if (!installed) {
        statusText = '未安装 Shizuku';
      } else if (!running) {
        statusText = 'Shizuku 未运行';
      } else if (!granted) {
        statusText = '未授权';
      } else {
        statusText = '已授权';
        await prefs.setBool('shizuku_mode_enabled', true);
      }
      capabilities[FileAccessMode.shizuku] = capabilities[
              FileAccessMode.shizuku]!
          .copyWith(
        enabled: granted ? true : shizukuWasEnabled,
        statusText: statusText,
        isChecking: false,
      );
    } catch (e) {
      for (final mode in capabilities.keys) {
        capabilities[mode] = capabilities[mode]!.copyWith(isChecking: false);
      }
    }
    notifyListeners();
  }

  /// Determine the effective access mode based on enabled capabilities and
  /// the target path.
  FileAccessMode effectiveModeForPath(String path) {
    final rootEnabled = capabilities[FileAccessMode.root]!.enabled;
    if (rootEnabled && path.startsWith('/')) {
      return FileAccessMode.root;
    }
    if (capabilities[FileAccessMode.shizuku]!.enabled &&
        path.contains('/Android/data/')) {
      return FileAccessMode.shizuku;
    }
    if (capabilities[FileAccessMode.manageAllFiles]!.enabled &&
        path.startsWith('/storage/')) {
      return FileAccessMode.manageAllFiles;
    }
    return FileAccessMode.normal;
  }

  /// [forcedMode] — when non-null, try this mode first, while still allowing
  /// root fallback for paths that root can access but normal/Shizuku cannot.
  List<FileAccessMode> candidateModesForPath(String path,
      {FileAccessMode? forcedMode}) {
    final candidates = <FileAccessMode>[];

    void add(FileAccessMode mode) {
      if (!candidates.contains(mode)) {
        candidates.add(mode);
      }
    }

    final rootEnabled = capabilities[FileAccessMode.root]!.enabled;
    final shizukuEnabled = capabilities[FileAccessMode.shizuku]!.enabled;
    final allFilesEnabled = capabilities[FileAccessMode.manageAllFiles]!.enabled;
    final isProtectedPath = path.startsWith('/data/') || path.startsWith('/system/');
    final isAndroidDataPath = path.contains('/Android/data/');
    final isStoragePath = path.startsWith('/storage/') || path.startsWith('/sdcard/');

    if (forcedMode != null) {
      add(forcedMode);
    }

    // In root mode, root is the universal privileged backend: it must be able
    // to browse both private app data (/data/user/0) and scoped storage paths.
    if (rootEnabled || forcedMode == FileAccessMode.root) {
      add(FileAccessMode.root);
    }

    if (forcedMode == null) {
      add(effectiveModeForPath(path));
    }

    if (isStoragePath && allFilesEnabled) {
      add(FileAccessMode.manageAllFiles);
    }

    if (isAndroidDataPath && shizukuEnabled) {
      add(FileAccessMode.shizuku);
    }

    final normalCannotWork = isProtectedPath || isAndroidDataPath;
    final forcedPrivileged = forcedMode == FileAccessMode.root ||
        forcedMode == FileAccessMode.shizuku;
    if (!normalCannotWork && !forcedPrivileged) {
      add(FileAccessMode.normal);
    }
    return candidates;
  }

  List<DirectoryEntry> _withFullPaths(
      String path, List<DirectoryEntry> entries) {
    final separator = path.endsWith('/') ? '' : '/';
    return entries.map((e) {
      return DirectoryEntry(
        name: e.name,
        isDirectory: e.isDirectory,
        fullPath: '$path$separator${e.name}',
      );
    }).toList();
  }

  // --- File operations ---

  /// List directory using the appropriate access mode.
  Future<List<DirectoryEntry>> listDirectory(String path,
      {FileAccessMode? forcedMode}) async {
    await ensureInitialized();
    final candidates = candidateModesForPath(path, forcedMode: forcedMode);
    final errors = <String>[];
    List<DirectoryEntry>? emptyFallback;
    for (var i = 0; i < candidates.length; i++) {
      final mode = candidates[i];
      try {
        final entries = _withFullPaths(
          path,
          await _access.listDirectory(path, mode: mode),
        );
        final hasLaterPrivilegedMode = candidates
            .skip(i + 1)
            .any((m) => m == FileAccessMode.root || m == FileAccessMode.shizuku);
        final suspiciousEmpty = entries.isEmpty &&
            hasLaterPrivilegedMode &&
            (mode == FileAccessMode.normal ||
                mode == FileAccessMode.manageAllFiles) &&
            (forcedMode != null ||
                path.contains('/Android/data/') ||
                path.startsWith('/storage/'));
        if (!suspiciousEmpty) {
          return entries;
        }
        emptyFallback ??= entries;
        errors.add('${fileAccessModeName(mode)}: empty result, trying privileged fallback');
      } catch (error) {
        errors.add('${fileAccessModeName(mode)}: $error');
      }
    }
    if (emptyFallback != null && errors.every((e) => e.contains('empty result'))) {
      return emptyFallback;
    }
    throw Exception(
        'Failed to list directory: $path\n${errors.join('\n')}');
  }

  /// Open a database file using the appropriate access mode.
  Future<DatabaseOpenSession> openDatabaseFile(String sourcePath,
      {FileAccessMode? forcedMode}) async {
    await ensureInitialized();
    final candidates =
        candidateModesForPath(sourcePath, forcedMode: forcedMode);
    final errors = <String>[];
    for (final mode in candidates) {
      try {
        final workPath =
            mode == FileAccessMode.root || mode == FileAccessMode.shizuku
                ? await _access.copyToWorkDirPrivileged(sourcePath, mode: mode)
                : await _access.copyToWorkDir(sourcePath);
        return DatabaseOpenSession(
          sourcePath: sourcePath,
          workPath: workPath,
          accessMode: mode,
          openedAt: DateTime.now(),
        );
      } catch (error) {
        errors.add('${fileAccessModeName(mode)}: $error');
      }
    }
    throw Exception(
        'Failed to open database: $sourcePath\n${errors.join('\n')}');
  }

  /// Save working copy back to source using the appropriate access mode.
  Future<void> saveBackToSource(String workPath, String sourcePath) async {
    await ensureInitialized();
    final mode = effectiveModeForPath(sourcePath);
    await _access.writeBackToSource(workPath, sourcePath, mode: mode);
  }

  // --- Convenience methods for UI ---

  Future<void> openManageAllFilesSettings() =>
      _access.openManageAllFilesAccessSettings();

  Future<void> openShizukuApp() => _access.openShizukuApp();

  Future<bool> requestShizukuPermission() =>
      _access.requestShizukuPermission();
}

final fileAccessControllerProvider =
    ChangeNotifierProvider<FileAccessController>((ref) {
  return FileAccessController();
});