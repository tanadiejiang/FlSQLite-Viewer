import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  List<DirectoryEntry> get files => entries.where((e) => !e.isDirectory).toList();

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

  static const testPaths = <Map<String, String>>[
    {
      'label': 'Root 测试路径',
      'path': '/data/user/0/com.deepseek.chat/download/download.db',
      'mode': 'root',
    },
    {
      'label': 'Shizuku 测试路径',
      'path': '/storage/emulated/0/Android/data/com.deepseek.chat/download.db',
      'mode': 'shizuku',
    },
    {
      'label': '普通/备份目录',
      'path': '/storage/emulated/0/1/.1临时文件/download.db',
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
      _allEntries = await _accessController.listDirectory(path,
          forcedMode: forcedMode);
      _currentPath = path;
      if (pathChanged && _filter.isNotEmpty) {
        _filter = '';
      }
      _addRecentPath(path);
    } catch (e) {
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

    _isLoading = false;
    notifyListeners();
  }

  void goUp() {
    if (_currentPath == '/') return;
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
    if (_currentPath == '/') return ['/'];
    return ['/', ..._currentPath.split('/').where((s) => s.isNotEmpty)];
  }

  String buildChildPath(String segment) {
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
}

final fileBrowserControllerProvider =
    ChangeNotifierProvider<FileBrowserController>((ref) {
  final accessController = ref.watch(fileAccessControllerProvider);
  return FileBrowserController(accessController);
});