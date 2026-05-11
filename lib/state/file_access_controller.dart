import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/file_session/android_special_file_access.dart';
import '../../core/file_session/database_file_access.dart';
import '../../models/database_models.dart';

class AccessModeUnavailableException implements Exception {
  final FileAccessMode mode;
  final String message;

  const AccessModeUnavailableException(this.mode, this.message);

  @override
  String toString() => message;
}

/// Manages Android file access modes, permissions, and directory browsing state.
class FileAccessController extends ChangeNotifier {
  static const _manageAllFilesPrefKey = 'manage_all_files_enabled';
  static const _rootPrefKey = 'root_mode_enabled';
  static const _shizukuPrefKey = 'shizuku_mode_enabled';

  final AndroidSpecialFileAccess _access = AndroidSpecialFileAccess();
  final NormalFileAccess _normalAccess = NormalFileAccess();

  AndroidSpecialFileAccess get access => _access;
  NormalFileAccess get normalAccess => _normalAccess;

  bool _initialized = false;

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

  /// Ensure saved access preferences are loaded at least once before any file
  /// operation. Safe to call multiple times — loads only on first invocation.
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await loadPreferences();
    _initialized = true;
  }

  Future<void> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    capabilities[FileAccessMode.root] = capabilities[FileAccessMode.root]!
        .copyWith(enabled: prefs.getBool(_rootPrefKey) ?? false);
    capabilities[FileAccessMode.shizuku] = capabilities[FileAccessMode.shizuku]!
        .copyWith(enabled: prefs.getBool(_shizukuPrefKey) ?? false);
    capabilities[FileAccessMode.manageAllFiles] =
        capabilities[FileAccessMode.manageAllFiles]!
            .copyWith(enabled: prefs.getBool(_manageAllFilesPrefKey) ?? false);
    notifyListeners();
  }

  Future<void> setCapabilityEnabled(FileAccessMode mode, bool enabled) async {
    capabilities[mode] = capabilities[mode]!.copyWith(enabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    final key = _preferenceKeyForMode(mode);
    if (key != null) {
      await prefs.setBool(key, enabled);
    }
    notifyListeners();
  }

  Future<void> checkAllStatuses({bool forceRefresh = false}) async {
    for (final mode in capabilities.keys) {
      capabilities[mode] = capabilities[mode]!.copyWith(isChecking: true);
    }
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();

      final hasAllFiles = await _access.hasManageAllFilesAccess();
      final allFilesEnabled = _storedEnabledWithFallback(
        prefs,
        _manageAllFilesPrefKey,
        fallback: hasAllFiles,
      );
      capabilities[FileAccessMode.manageAllFiles] =
          capabilities[FileAccessMode.manageAllFiles]!.copyWith(
        enabled: allFilesEnabled,
        available: hasAllFiles,
        statusText: hasAllFiles ? '已授权' : '未授权',
        isChecking: false,
      );
      await _persistDefaultIfMissing(
        prefs,
        _manageAllFilesPrefKey,
        allFilesEnabled,
      );

      final hasRoot = await _access.hasRootAccess(forceRefresh: forceRefresh);
      final rootEnabled = _storedEnabledWithFallback(
        prefs,
        _rootPrefKey,
        fallback: hasRoot,
      );
      capabilities[FileAccessMode.root] = capabilities[FileAccessMode.root]!
          .copyWith(
        enabled: rootEnabled,
        available: hasRoot,
        statusText: hasRoot ? 'Root 可用' : 'Root 不可用',
        isChecking: false,
      );
      await _persistDefaultIfMissing(prefs, _rootPrefKey, rootEnabled);

      final shizukuStatus =
          await _access.getShizukuStatus(forceRefresh: forceRefresh);
      final installed = shizukuStatus['installed'] == true;
      final running = shizukuStatus['running'] == true;
      final granted = shizukuStatus['permissionGranted'] == true;
      final shizukuEnabled = _storedEnabledWithFallback(
        prefs,
        _shizukuPrefKey,
        fallback: granted,
      );
      String statusText;
      if (!installed) {
        statusText = '未安装 Shizuku';
      } else if (!running) {
        statusText = 'Shizuku 未运行';
      } else if (!granted) {
        statusText = '未授权';
      } else {
        statusText = '已授权';
      }
      capabilities[FileAccessMode.shizuku] =
          capabilities[FileAccessMode.shizuku]!.copyWith(
        enabled: shizukuEnabled,
        available: granted,
        statusText: statusText,
        isChecking: false,
      );
      await _persistDefaultIfMissing(prefs, _shizukuPrefKey, shizukuEnabled);
    } catch (e) {
      for (final mode in capabilities.keys) {
        capabilities[mode] = capabilities[mode]!.copyWith(isChecking: false);
      }
    }
    notifyListeners();
  }

  bool canUseMode(FileAccessMode mode) {
    if (mode == FileAccessMode.normal) {
      return true;
    }
    final capability = capabilities[mode];
    return capability != null && capability.enabled && capability.available;
  }

  String accessModeUnavailableMessage(FileAccessMode mode) {
    switch (mode) {
      case FileAccessMode.root:
        return 'Root 权限无/或未启用';
      case FileAccessMode.shizuku:
        return 'Shizuku 权限无/或未启用';
      case FileAccessMode.manageAllFiles:
        return '全部文件访问无/或未启用';
      case FileAccessMode.normal:
        return '普通目录访问不可用';
    }
  }

  void _ensureModeUsableOrThrow(FileAccessMode mode) {
    if (!canUseMode(mode)) {
      throw AccessModeUnavailableException(
        mode,
        accessModeUnavailableMessage(mode),
      );
    }
  }

  FileAccessMode effectiveModeForPath(String path) {
    final candidates = candidateModesForPath(path);
    return candidates.isEmpty ? FileAccessMode.normal : candidates.first;
  }

  /// [forcedMode] — when non-null, try this mode first.
  ///
  /// Normal file browsing still prefers low-privilege modes for storage paths,
  /// while protected absolute paths use the active privileged chain:
  /// Root → Shizuku → 全部文件访问 → 普通模式。
  List<FileAccessMode> candidateModesForPath(String path,
      {FileAccessMode? forcedMode}) {
    final candidates = <FileAccessMode>[];

    void add(FileAccessMode mode) {
      if (!candidates.contains(mode)) {
        candidates.add(mode);
      }
    }

    void addIfActive(FileAccessMode mode) {
      if (canUseMode(mode)) {
        add(mode);
      }
    }

    final isProtectedPath =
        path == '/data' ||
        path == '/system' ||
        path.startsWith('/data/') ||
        path.startsWith('/system/');
    final isAndroidDataPath = path.contains('/Android/data/');
    final isStoragePath =
        path.startsWith('/storage/') || path.startsWith('/sdcard/');
    final isAbsolutePath = path == '/' || path.startsWith('/');
    final isPrivilegedAbsolutePath =
        isProtectedPath || (isAbsolutePath && !isStoragePath);

    if (forcedMode == FileAccessMode.root ||
        forcedMode == FileAccessMode.shizuku) {
      add(forcedMode!);
      return candidates;
    }

    if (forcedMode != null) {
      add(forcedMode);
    }

    if (isPrivilegedAbsolutePath) {
      addIfActive(FileAccessMode.root);
      addIfActive(FileAccessMode.shizuku);
      addIfActive(FileAccessMode.manageAllFiles);
      add(FileAccessMode.normal);
      return candidates;
    }

    add(FileAccessMode.normal);

    if (isAndroidDataPath) {
      addIfActive(FileAccessMode.manageAllFiles);
      addIfActive(FileAccessMode.shizuku);
      addIfActive(FileAccessMode.root);
      return candidates;
    }

    if (isStoragePath) {
      addIfActive(FileAccessMode.manageAllFiles);
      addIfActive(FileAccessMode.root);
      return candidates;
    }

    addIfActive(FileAccessMode.manageAllFiles);
    addIfActive(FileAccessMode.shizuku);
    addIfActive(FileAccessMode.root);
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

  Future<List<DirectoryEntry>> listDirectory(String path,
      {FileAccessMode? forcedMode}) async {
    await ensureInitialized();
    if (forcedMode != null && forcedMode != FileAccessMode.normal) {
      _ensureModeUsableOrThrow(forcedMode);
    }

    final candidates = candidateModesForPath(path, forcedMode: forcedMode);
    final errors = <String>[];
    List<DirectoryEntry>? emptyFallback;
    List<DirectoryEntry>? partialFallback;

    for (var i = 0; i < candidates.length; i++) {
      final mode = candidates[i];
      try {
        final entries = _withFullPaths(
          path,
          await _access.listDirectory(path, mode: mode),
        );
        final hasLaterMoreCapableMode = candidates
            .skip(i + 1)
            .any((m) => _modePrivilegeRank(m) > _modePrivilegeRank(mode));
        final suspiciousEmpty = entries.isEmpty &&
            hasLaterMoreCapableMode &&
            (mode == FileAccessMode.normal ||
                mode == FileAccessMode.manageAllFiles) &&
            (forcedMode != FileAccessMode.root &&
                forcedMode != FileAccessMode.shizuku) &&
            (forcedMode != null ||
                path.contains('/Android/data/') ||
                path.startsWith('/storage/'));
        final preferPrivilegedStorageListing = entries.isNotEmpty &&
            hasLaterMoreCapableMode &&
            (mode == FileAccessMode.normal ||
                mode == FileAccessMode.manageAllFiles) &&
            forcedMode != FileAccessMode.root &&
            forcedMode != FileAccessMode.shizuku &&
            (path.startsWith('/storage/') || path.startsWith('/sdcard/'));
        if (!suspiciousEmpty && !preferPrivilegedStorageListing) {
          return entries;
        }
        if (preferPrivilegedStorageListing) {
          partialFallback ??= entries;
        } else {
          emptyFallback ??= entries;
        }
        errors.add(preferPrivilegedStorageListing
            ? '${fileAccessModeName(mode)}: partial visibility risk, trying privileged fallback'
            : '${fileAccessModeName(mode)}: empty result, trying privileged fallback');
      } catch (error) {
        errors.add('${fileAccessModeName(mode)}: $error');
      }
    }
    if (partialFallback != null) {
      return partialFallback;
    }
    if (emptyFallback != null &&
        errors.every((e) => e.contains('empty result'))) {
      return emptyFallback;
    }
    throw Exception('Failed to list directory: $path\n${errors.join('\n')}');
  }

  Future<DatabaseOpenSession> openDatabaseFile(String sourcePath,
      {FileAccessMode? forcedMode}) async {
    await ensureInitialized();
    if (forcedMode != null && forcedMode != FileAccessMode.normal) {
      _ensureModeUsableOrThrow(forcedMode);
    }

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
    throw Exception('Failed to open database: $sourcePath\n${errors.join('\n')}');
  }

  Future<void> saveBackToSource(String workPath, String sourcePath) async {
    await ensureInitialized();
    final mode = effectiveModeForPath(sourcePath);
    await _access.writeBackToSource(workPath, sourcePath, mode: mode);
  }

  Future<void> openManageAllFilesSettings() =>
      _access.openManageAllFilesAccessSettings();

  Future<void> openShizukuApp() => _access.openShizukuApp();

  Future<bool> requestShizukuPermission() =>
      _access.requestShizukuPermission();

  String? _preferenceKeyForMode(FileAccessMode mode) {
    switch (mode) {
      case FileAccessMode.manageAllFiles:
        return _manageAllFilesPrefKey;
      case FileAccessMode.root:
        return _rootPrefKey;
      case FileAccessMode.shizuku:
        return _shizukuPrefKey;
      case FileAccessMode.normal:
        return null;
    }
  }

  bool _storedEnabledWithFallback(
    SharedPreferences prefs,
    String key, {
    required bool fallback,
  }) {
    if (prefs.containsKey(key)) {
      return prefs.getBool(key) ?? false;
    }
    return fallback;
  }

  Future<void> _persistDefaultIfMissing(
    SharedPreferences prefs,
    String key,
    bool value,
  ) async {
    if (!prefs.containsKey(key)) {
      await prefs.setBool(key, value);
    }
  }

  int _modePrivilegeRank(FileAccessMode mode) {
    switch (mode) {
      case FileAccessMode.normal:
        return 0;
      case FileAccessMode.manageAllFiles:
        return 1;
      case FileAccessMode.shizuku:
        return 2;
      case FileAccessMode.root:
        return 3;
    }
  }
}

final fileAccessControllerProvider =
    ChangeNotifierProvider<FileAccessController>((ref) {
  return FileAccessController();
});