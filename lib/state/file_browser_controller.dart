import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_strings.dart';
import '../../models/database_models.dart';
import 'file_access_controller.dart';

/// Manages file browser state: current path, directory listing, filtering,
/// recent paths, and test path shortcuts.
class FileBrowserController extends ChangeNotifier {
  final FileAccessController _accessController;

  FileBrowserController(this._accessController);

  // --- State ---

  String _currentPath = '/';
  String get currentPath => _currentPath;

  List<DirectoryEntry> _allEntries = [];
  List<DirectoryEntry> get entries {
    final keyword = _filter.toLowerCase();
    return _allEntries.where((entry) {
      final matchesFilter =
          keyword.isEmpty || entry.name.toLowerCase().contains(keyword);
      if (!matchesFilter) {
        return false;
      }
      if (!_showDatabasesOnly) {
        return true;
      }
      return entry.isDirectory || isDatabaseFile(entry.name);
    }).toList();
  }

  List<DirectoryEntry> get directories =>
      entries.where((e) => e.isDirectory).toList();
  List<DirectoryEntry> get files =>
      entries.where((e) => !e.isDirectory).toList();

  String _filter = '';
  String get filter => _filter;

  bool _showDatabasesOnly = false;
  bool get showDatabasesOnly => _showDatabasesOnly;

  List<String> _recentPaths = [];
  List<String> get recentPaths => _recentPaths;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorSummary;
  String? get errorMessage => _errorSummary;
  String? get errorSummary => _errorSummary;

  String? _errorDetails;
  String? get errorDetails => _errorDetails;

  // --- Test path shortcuts ---

  static List<Map<String, String>> get testPaths => [
    {
      'label': AppStrings.current.rootTestPath,
      'path': '/data/user/0/',
      'mode': 'root',
    },
    {
      'label': AppStrings.current.shizukuTestPath,
      'path': '/storage/emulated/0/Android/data/',
      'mode': 'shizuku',
    },
    {
      'label': AppStrings.current.backupDirectory,
      'path': '/storage/emulated/0/',
    },
  ];

  // Last forced mode, preserved for retry.
  FileAccessMode? _lastForcedMode;
  FileAccessMode? get lastForcedMode => _lastForcedMode;

  // --- Navigation ---
  Future<void> navigateTo(String path, {FileAccessMode? forcedMode}) async {
    final pathChanged = path != _currentPath;
    _lastForcedMode = forcedMode;
    _isLoading = true;
    _errorSummary = null;
    _errorDetails = null;
    notifyListeners();

    try {
      _allEntries = await _accessController.listDirectory(
        path,
        forcedMode: forcedMode,
      );
      _currentPath = path;
      if (pathChanged && _filter.isNotEmpty) {
        _filter = '';
      }
      _addRecentPath(path);
    } catch (e) {
      if (e is FileAccessFailureException) {
        _errorSummary = e.summary;
        _errorDetails = e.details;
      } else {
        final modes = _accessController
            .candidateModesForPath(path, forcedMode: forcedMode)
            .map(fileAccessModeName)
            .join(' → ');
        final detail = '$e\nTried modes: $modes'
            .replaceFirst('Exception: ', '')
            .trim();
        _errorDetails = detail;
        _errorSummary = detail.split('\n').first.trim();
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  void goUp() {
    if (_currentPath == '/') return;
    if (Platform.isWindows) {
      final normalized = p.normalize(_currentPath);
      final root = p.rootPrefix(normalized);
      if (root.isNotEmpty && normalized == root) {
        return;
      }
      final parent = p.dirname(normalized);
      navigateTo(parent == '.' ? root : parent);
      return;
    }
    final parent = _currentPath.substring(0, _currentPath.lastIndexOf('/'));
    navigateTo(parent.isEmpty ? '/' : parent);
  }

  /// Retry the current directory listing, preserving the last forced mode.
  void retry() {
    navigateTo(_currentPath, forcedMode: _lastForcedMode);
  }

  void setFilter(String filter) {
    _filter = filter;
    notifyListeners();
  }

  void setShowDatabasesOnly(bool value) {
    if (_showDatabasesOnly == value) {
      return;
    }
    _showDatabasesOnly = value;
    notifyListeners();
  }

  void _addRecentPath(String path) {
    _recentPaths.remove(path);
    _recentPaths.insert(0, path);
    if (_recentPaths.length > 10) {
      _recentPaths = _recentPaths.sublist(0, 10);
    }
  }

  // --- Path parsing helpers ---

  List<String> get pathSegments {
    if (Platform.isWindows) {
      final normalized = p.normalize(_currentPath);
      final root = p.rootPrefix(normalized);
      if (root.isEmpty) {
        return [normalized];
      }
      final relative = normalized.substring(root.length);
      return [
        root,
        ...relative
            .split(RegExp(r'[\\/]'))
            .where((segment) => segment.isNotEmpty),
      ];
    }
    if (_currentPath == '/') return ['/'];
    return ['/', ..._currentPath.split('/').where((s) => s.isNotEmpty)];
  }

  String pathForSegmentIndex(int index) {
    if (!Platform.isWindows) {
      final segments = pathSegments;
      final path = segments.take(index + 1).join('/').replaceAll('//', '/');
      return path.isEmpty ? '/' : path;
    }
    final segments = pathSegments;
    if (segments.isEmpty) {
      return _currentPath;
    }
    if (index <= 0) {
      return segments.first;
    }
    return p.joinAll(segments.take(index + 1).toList());
  }

  String buildChildPath(String segment) {
    if (Platform.isWindows) {
      return p.join(_currentPath, segment);
    }
    if (_currentPath == '/') return '/$segment';
    return '$_currentPath/$segment';
  }

  void clearError() {
    _errorSummary = null;
    _errorDetails = null;
    notifyListeners();
  }

  // --- Database selection ---

  bool isDatabaseFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.db') ||
        lower.endsWith('.sqlite') ||
        lower.endsWith('.sqlite3');
  }

  List<DirectoryEntry> get databaseFiles =>
      files.where((f) => isDatabaseFile(f.name)).toList();

  bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<String> defaultInitialPath() async {
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        final documents = p.join(userProfile, 'Documents');
        if (await Directory(documents).exists()) {
          return documents;
        }
        if (await Directory(userProfile).exists()) {
          return userProfile;
        }
      }
      final drives = _availableWindowsDrives();
      return drives.isNotEmpty ? drives.first.fullPath : 'C:\\';
    }
    if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return home;
      }
    }
    return '/storage/emulated/0/';
  }

  List<DirectoryEntry> get desktopShortcutEntries {
    if (!Platform.isWindows) {
      return const [];
    }
    return _availableWindowsDrives();
  }

  List<DirectoryEntry> _availableWindowsDrives() {
    final drives = <DirectoryEntry>[];
    for (var code = 65; code <= 90; code++) {
      final letter = String.fromCharCode(code);
      final root = '$letter:\\';
      if (Directory(root).existsSync()) {
        drives.add(
          DirectoryEntry(
            name: root,
            isDirectory: true,
            fullPath: root,
          ),
        );
      }
    }
    return drives;
  }
}

final fileBrowserControllerProvider =
    ChangeNotifierProvider<FileBrowserController>((ref) {
      final accessController = ref.watch(fileAccessControllerProvider);
      return FileBrowserController(accessController);
    });
