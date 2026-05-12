import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/file_session/android_special_file_access.dart';
import '../../core/file_session/database_file_access.dart';
import '../../l10n/app_strings.dart';
import '../../models/database_models.dart';

class AccessModeUnavailableException implements Exception {
  final FileAccessMode mode;
  final String message;

  const AccessModeUnavailableException(this.mode, this.message);

  @override
  String toString() => message;
}

class FileAccessFailureException implements Exception {
  final String summary;
  final String details;

  const FileAccessFailureException({
    required this.summary,
    required this.details,
  });

  @override
  String toString() => details;
}

/// Manages Android file access modes, permissions, and directory browsing state.
class FileAccessController extends ChangeNotifier {
  static const _manageAllFilesPrefKey = 'manage_all_files_enabled';
  static const _rootPrefKey = 'root_mode_enabled';
  static const _shizukuPrefKey = 'shizuku_mode_enabled';

  FileAccessController() {
    _applyLocalizedCapabilities();
  }

  final AndroidSpecialFileAccess _access = AndroidSpecialFileAccess();
  final NormalFileAccess _normalAccess = NormalFileAccess();

  bool _allFilesAvailable = false;
  bool _rootAvailable = false;
  bool _shizukuInstalled = false;
  bool _shizukuRunning = false;
  bool _shizukuGranted = false;

  AndroidSpecialFileAccess get access => _access;
  NormalFileAccess get normalAccess => _normalAccess;

  bool _initialized = false;

  final Map<FileAccessMode, AccessCapability> capabilities = {
    FileAccessMode.manageAllFiles: const AccessCapability(
      mode: FileAccessMode.manageAllFiles,
      label: '',
      description: '',
    ),
    FileAccessMode.root: const AccessCapability(
      mode: FileAccessMode.root,
      label: '',
      description: '',
    ),
    FileAccessMode.shizuku: const AccessCapability(
      mode: FileAccessMode.shizuku,
      label: '',
      description: '',
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
    _applyLocalizedCapabilities();
    notifyListeners();
  }

  Future<void> setCapabilityEnabled(FileAccessMode mode, bool enabled) async {
    capabilities[mode] = capabilities[mode]!.copyWith(enabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    final key = _preferenceKeyForMode(mode);
    if (key != null) {
      await prefs.setBool(key, enabled);
    }
    _applyLocalizedCapabilities();
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
      _allFilesAvailable = hasAllFiles;
      final allFilesEnabled = _storedEnabledWithFallback(
        prefs,
        _manageAllFilesPrefKey,
        fallback: hasAllFiles,
      );
      capabilities[FileAccessMode.manageAllFiles] =
          capabilities[FileAccessMode.manageAllFiles]!.copyWith(
        enabled: allFilesEnabled,
        available: hasAllFiles,
        label: AppStrings.current.accessManageAllFilesLabel,
        description: AppStrings.current.accessManageAllFilesDescription,
        statusText: hasAllFiles
            ? AppStrings.current.authorized
            : AppStrings.current.unauthorized,
        isChecking: false,
      );
      await _persistDefaultIfMissing(
        prefs,
        _manageAllFilesPrefKey,
        allFilesEnabled,
      );

      final hasRoot = await _access.hasRootAccess(forceRefresh: forceRefresh);
      _rootAvailable = hasRoot;
      final rootEnabled = _storedEnabledWithFallback(
        prefs,
        _rootPrefKey,
        fallback: hasRoot,
      );
      capabilities[FileAccessMode.root] = capabilities[FileAccessMode.root]!
          .copyWith(
        enabled: rootEnabled,
        available: hasRoot,
        label: AppStrings.current.accessRootLabel,
        description: AppStrings.current.accessRootDescription,
        statusText: hasRoot
            ? AppStrings.current.rootAvailable
            : AppStrings.current.rootUnavailable,
        isChecking: false,
      );
      await _persistDefaultIfMissing(prefs, _rootPrefKey, rootEnabled);

      final shizukuStatus =
          await _access.getShizukuStatus(forceRefresh: forceRefresh);
      final installed = shizukuStatus['installed'] == true;
      final running = shizukuStatus['running'] == true;
      final granted = shizukuStatus['permissionGranted'] == true;
      _shizukuInstalled = installed;
      _shizukuRunning = running;
      _shizukuGranted = granted;
      final shizukuEnabled = _storedEnabledWithFallback(
        prefs,
        _shizukuPrefKey,
        fallback: granted,
      );
      String statusText;
      if (!installed) {
        statusText = AppStrings.current.shizukuNotInstalled;
      } else if (!running) {
        statusText = AppStrings.current.shizukuNotRunning;
      } else if (!granted) {
        statusText = AppStrings.current.unauthorized;
      } else {
        statusText = AppStrings.current.authorized;
      }
      capabilities[FileAccessMode.shizuku] =
          capabilities[FileAccessMode.shizuku]!.copyWith(
        enabled: shizukuEnabled,
        available: granted,
        label: AppStrings.current.accessShizukuLabel,
        description: AppStrings.current.accessShizukuDescription,
        statusText: statusText,
        isChecking: false,
      );
      await _persistDefaultIfMissing(prefs, _shizukuPrefKey, shizukuEnabled);
    } catch (e) {
      for (final mode in capabilities.keys) {
        capabilities[mode] = capabilities[mode]!.copyWith(isChecking: false);
      }
    }
    _applyLocalizedCapabilities();
    notifyListeners();
  }

  Future<void> refreshLocalization() async {
    _applyLocalizedCapabilities();
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
        return AppStrings.current.rootUnavailableOrDisabled;
      case FileAccessMode.shizuku:
        return AppStrings.current.shizukuUnavailableOrDisabled;
      case FileAccessMode.manageAllFiles:
        return AppStrings.current.allFilesUnavailableOrDisabled;
      case FileAccessMode.normal:
        return AppStrings.current.normalAccessUnavailable;
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

    if (forcedMode == FileAccessMode.root) {
      add(forcedMode!);
      return candidates;
    }

    if (forcedMode != null &&
        (forcedMode == FileAccessMode.normal || canUseMode(forcedMode))) {
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
      addIfActive(FileAccessMode.shizuku);
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
    if (forcedMode == FileAccessMode.root) {
      _ensureModeUsableOrThrow(forcedMode!);
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
            forcedMode != FileAccessMode.root &&
            (forcedMode != null ||
                path.contains('/Android/data/') ||
                path.startsWith('/storage/'));
        final preferPrivilegedStorageListing = entries.isNotEmpty &&
            hasLaterMoreCapableMode &&
            (mode == FileAccessMode.normal ||
                mode == FileAccessMode.manageAllFiles) &&
            forcedMode != FileAccessMode.root &&
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
    throw _buildAccessFailure(
      operationLabel: AppStrings.current.listDirectoryAction,
      path: path,
      candidates: candidates,
      errors: errors,
    );
  }

  Future<DatabaseOpenSession> openDatabaseFile(String sourcePath,
      {FileAccessMode? forcedMode}) async {
    await ensureInitialized();
    if (forcedMode == FileAccessMode.root) {
      _ensureModeUsableOrThrow(forcedMode!);
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
    throw _buildAccessFailure(
      operationLabel: AppStrings.current.openDatabaseAction,
      path: sourcePath,
      candidates: candidates,
      errors: errors,
    );
  }

  Future<void> saveBackToSource(
    String workPath,
    String sourcePath, {
    FileAccessMode? preferredMode,
  }) async {
    await ensureInitialized();
    final mode = preferredMode ?? effectiveModeForPath(sourcePath);
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

  FileAccessFailureException _buildAccessFailure({
    required String operationLabel,
    required String path,
    required List<FileAccessMode> candidates,
    required List<String> errors,
  }) {
    final summary = _friendlyAccessFailureSummary(
      operationLabel: operationLabel,
      path: path,
      candidates: candidates,
      errors: errors,
    );
    final detail = StringBuffer(summary)
      ..writeln()
      ..writeln('Path: $path')
      ..writeln('Tried modes: ${candidates.map(fileAccessModeName).join(' → ')}');
    for (final error in errors) {
      detail.writeln(error);
    }
    return FileAccessFailureException(
      summary: summary,
      details: detail.toString().trim(),
    );
  }

  String _friendlyAccessFailureSummary({
    required String operationLabel,
    required String path,
    required List<FileAccessMode> candidates,
    required List<String> errors,
  }) {
    if (_isAndroidRestrictedPath(path)) {
      final triedPrivileged =
          candidates.contains(FileAccessMode.shizuku) ||
          candidates.contains(FileAccessMode.root);
      if (!triedPrivileged) {
        return AppStrings.current.restrictedDirectoryNeedPrivileged;
      }
      final privilegedFailed = errors.any((error) {
        final lower = error.toLowerCase();
        return (lower.contains('shizuku:') || lower.contains('root:')) &&
            _isPermissionLikeError(lower);
      });
      if (privilegedFailed) {
        return AppStrings.current.restrictedDirectoryStillFailed;
      }
      return operationLabel == AppStrings.current.openDatabaseAction
          ? AppStrings.current.restrictedDatabaseNeedPrivileged
          : AppStrings.current.restrictedDirectoryNeedShizukuOrRoot;
    }

    return AppStrings.current.actionFailed(operationLabel, path);
  }

  bool _isAndroidRestrictedPath(String path) {
    return path == '/storage/emulated/0/Android' ||
        path.startsWith('/storage/emulated/0/Android/') ||
        path == '/sdcard/Android' ||
        path.startsWith('/sdcard/Android/');
  }

  bool _isPermissionLikeError(String value) {
    return value.contains('permission denied') ||
        value.contains('operation not permitted') ||
        value.contains('errno = 13') ||
        value.contains('pathaccessexception') ||
        value.contains('no such file or directory');
  }

  void _applyLocalizedCapabilities() {
    capabilities[FileAccessMode.manageAllFiles] =
        capabilities[FileAccessMode.manageAllFiles]!.copyWith(
      label: AppStrings.current.accessManageAllFilesLabel,
      description: AppStrings.current.accessManageAllFilesDescription,
      statusText: _allFilesAvailable
          ? AppStrings.current.authorized
          : AppStrings.current.unauthorized,
    );
    capabilities[FileAccessMode.root] = capabilities[FileAccessMode.root]!.copyWith(
      label: AppStrings.current.accessRootLabel,
      description: AppStrings.current.accessRootDescription,
      statusText: _rootAvailable
          ? AppStrings.current.rootAvailable
          : AppStrings.current.rootUnavailable,
    );

    String shizukuStatus;
    if (!_shizukuInstalled) {
      shizukuStatus = AppStrings.current.shizukuNotInstalled;
    } else if (!_shizukuRunning) {
      shizukuStatus = AppStrings.current.shizukuNotRunning;
    } else if (!_shizukuGranted) {
      shizukuStatus = AppStrings.current.unauthorized;
    } else {
      shizukuStatus = AppStrings.current.authorized;
    }

    capabilities[FileAccessMode.shizuku] = capabilities[FileAccessMode.shizuku]!
        .copyWith(
      label: AppStrings.current.accessShizukuLabel,
      description: AppStrings.current.accessShizukuDescription,
      statusText: shizukuStatus,
    );
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