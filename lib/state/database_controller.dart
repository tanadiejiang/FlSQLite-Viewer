import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/data/sqlite_database_service.dart';
import '../../core/data/sqlite_repository.dart';
import '../../models/database_models.dart';
import 'file_access_controller.dart';

/// Central state for the active database session: schema, current table,
/// paged data, search, mutations, and recent-open history.
class DatabaseController extends ChangeNotifier {
  static const _historyPreferenceKey = 'database_open_history';

  final SqliteRepository _repository;

  DatabaseOpenSession? _currentSession;
  List<DatabaseHistoryEntry> _historyEntries = [];

  DatabaseController() : _repository = SqliteRepository(SqliteDatabaseService()) {
    Future.microtask(_loadHistory);
  }

  SqliteRepository get repository => _repository;
  bool get isOpen => _repository.isOpen;
  String? get currentPath => _currentSession?.sourcePath ?? _repository.currentPath;
  String? get currentSourcePath => _currentSession?.sourcePath;
  String? get currentWorkPath => _currentSession?.workPath;
  DatabaseOpenSession? get currentSession => _currentSession;
  List<DatabaseHistoryEntry> get historyEntries => List.unmodifiable(_historyEntries);

  // --- State ---

  List<String> _tableNames = [];
  List<String> get tableNames => _tableNames;

  String? _currentTable;
  String? get currentTable => _currentTable;

  DatabaseTable? _tableSchema;
  DatabaseTable? get tableSchema => _tableSchema;

  TablePage? _currentPage;
  TablePage? get currentPage => _currentPage;

  final int _pageSize = 50;
  int get pageSize => _pageSize;

  String? _searchTerm;
  String? get searchTerm => _searchTerm;

  String _orderBy = 'rowid DESC';
  String get orderBy => _orderBy;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _hasUnsavedChanges = false;
  bool get hasUnsavedChanges => _hasUnsavedChanges;

  bool _isSaving = false;
  bool get isSaving => _isSaving;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // --- Open / Close ---

  Future<void> openDatabase(
    DatabaseOpenSession session, {
    String? preferredTable,
    int? preferredPage,
    String? preferredSearch,
    String? preferredOrderBy,
  }) async {
    try {
      _currentSession = session;
      _repository.open(session.workPath);
      _tableNames = _repository.getTableNames();
      _searchTerm = preferredSearch?.trim().isEmpty == true
          ? null
          : preferredSearch?.trim();
      _orderBy = preferredOrderBy ?? _orderBy;

      final resolvedTable =
          preferredTable != null && _tableNames.contains(preferredTable)
              ? preferredTable
              : (_tableNames.isNotEmpty ? _tableNames.first : null);
      _currentTable = resolvedTable;
      _tableSchema =
          _currentTable != null ? _repository.getTable(_currentTable!) : null;
      _loadPage(page: preferredPage ?? 1);
      _hasUnsavedChanges = false;
      _isSaving = false;
      _errorMessage = null;
      await _recordHistory(lastTable: _currentTable);
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to open database: $e';
      notifyListeners();
    }
  }

  void closeDatabase() {
    _repository.close();
    _currentSession = null;
    _tableNames = [];
    _currentTable = null;
    _tableSchema = null;
    _currentPage = null;
    _hasUnsavedChanges = false;
    _isSaving = false;
    _errorMessage = null;
    notifyListeners();
  }

  // --- Table selection ---

  void selectTable(String tableName) {
    if (_currentTable == tableName) return;
    _currentTable = tableName;
    _tableSchema = _repository.getTable(tableName);
    _searchTerm = null;
    _loadPage();
    Future.microtask(() => _recordHistory(lastTable: tableName));
    notifyListeners();
  }

  // --- Query ---

  void _loadPage({int? page, bool silent = false}) {
    if (_currentTable == null) return;
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      _currentPage = _repository.queryPage(
        _currentTable!,
        page: page ?? 1,
        pageSize: _pageSize,
        searchTerm: _searchTerm,
        orderBy: _orderBy,
      );
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Query failed: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  void goToPage(int page) {
    if (page < 1) return;
    _loadPage(page: page);
  }

  void nextPage() {
    if (_currentPage == null || !_currentPage!.hasMore) return;
    goToPage(_currentPage!.currentPage + 1);
  }

  void prevPage() {
    if (_currentPage == null || _currentPage!.currentPage <= 1) return;
    goToPage(_currentPage!.currentPage - 1);
  }

  void setSearch(String? term) {
    _searchTerm = term?.trim().isEmpty == true ? null : term?.trim();
    _loadPage();
  }

  void setOrderBy(String order) {
    _orderBy = order;
    _loadPage();
  }

  void refresh() {
    final page = _currentPage?.currentPage ?? 1;
    _repository.refresh();
    _tableNames = _repository.getTableNames();
    if (_currentTable != null && _tableNames.contains(_currentTable)) {
      _tableSchema = _repository.getTable(_currentTable!);
    } else {
      _currentTable = _tableNames.isNotEmpty ? _tableNames.first : null;
      _tableSchema =
          _currentTable != null ? _repository.getTable(_currentTable!) : null;
    }
    _loadPage(page: page);
  }

  Future<void> refreshFromSource(FileAccessController access) async {
    final session = _currentSession;
    if (session == null) {
      refresh();
      return;
    }

    final selectedTable = _currentTable;
    final selectedPage = _currentPage?.currentPage ?? 1;
    final selectedSearch = _searchTerm;
    final selectedOrder = _orderBy;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final refreshedSession = await access.openDatabaseFile(
        session.sourcePath,
        forcedMode:
            session.accessMode == FileAccessMode.normal ? null : session.accessMode,
      );
      await openDatabase(
        refreshedSession,
        preferredTable: selectedTable,
        preferredPage: selectedPage,
        preferredSearch: selectedSearch,
        preferredOrderBy: selectedOrder,
      );
    } on AccessModeUnavailableException catch (e) {
      _isLoading = false;
      _errorMessage = e.message;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Refresh failed: $e';
      notifyListeners();
    }
  }

  // --- Mutations ---

  void insertRow(Map<String, dynamic> values) {
    if (_currentTable == null) return;
    try {
      _repository.insertRow(_currentTable!, values);
      _hasUnsavedChanges = true;
      _loadPage(page: _currentPage?.currentPage ?? 1);
    } catch (e) {
      _errorMessage = 'Insert failed: $e';
      notifyListeners();
    }
  }

  void updateRow(Map<String, dynamic> oldRow, Map<String, dynamic> newValues) {
    if (_currentTable == null) return;
    try {
      _repository.updateRow(_currentTable!, oldRow, newValues);
      _hasUnsavedChanges = true;
      refresh();
    } catch (e) {
      _errorMessage = 'Update failed: $e';
      notifyListeners();
    }
  }

  void deleteRow(Map<String, dynamic> row) {
    if (_currentTable == null) return;
    try {
      _repository.deleteRow(_currentTable!, row);
      _hasUnsavedChanges = true;
      _loadPage(page: _currentPage?.currentPage ?? 1);
    } catch (e) {
      _errorMessage = 'Delete failed: $e';
      notifyListeners();
    }
  }

  Future<void> saveChanges(FileAccessController access) async {
    final session = _currentSession;
    if (session == null || !_hasUnsavedChanges || _isSaving) {
      return;
    }

    final selectedTable = _currentTable;
    final selectedPage = _currentPage?.currentPage ?? 1;
    final selectedSearch = _searchTerm;
    final selectedOrder = _orderBy;

    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      try {
        _repository.service.executeRaw('PRAGMA wal_checkpoint(FULL)');
        _repository.service.executeRaw('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {}

      await access.saveBackToSource(session.workPath, session.sourcePath);
      _repository.refresh();
      _tableNames = _repository.getTableNames();
      _currentTable =
          selectedTable != null && _tableNames.contains(selectedTable)
              ? selectedTable
              : (_tableNames.isNotEmpty ? _tableNames.first : null);
      _tableSchema =
          _currentTable != null ? _repository.getTable(_currentTable!) : null;
      _searchTerm = selectedSearch;
      _orderBy = selectedOrder;
      _loadPage(page: selectedPage, silent: true);
      _hasUnsavedChanges = false;
      _errorMessage = null;
      await _recordHistory(lastTable: _currentTable, notify: false);
    } catch (e) {
      _errorMessage = 'Save failed: $e';
      try {
        _repository.refresh();
        if (_currentTable != null) {
          _tableSchema = _repository.getTable(_currentTable!);
        }
        _loadPage(page: selectedPage, silent: true);
      } catch (_) {}
    }

    _isSaving = false;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final rawEntries = prefs.getStringList(_historyPreferenceKey) ?? [];
    _historyEntries = rawEntries
        .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
        .map(DatabaseHistoryEntry.fromJson)
        .toList()
      ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    notifyListeners();
  }

  Future<void> _recordHistory({String? lastTable, bool notify = true}) async {
    final session = _currentSession;
    if (session == null) return;

    final displayName = session.sourcePath.split('/').last.isEmpty
        ? session.sourcePath
        : session.sourcePath.split('/').last;

    final updatedEntry = DatabaseHistoryEntry(
      sourcePath: session.sourcePath,
      displayName: displayName,
      accessMode: session.accessMode,
      lastOpenedAt: DateTime.now(),
      lastTable: lastTable,
    );

    _historyEntries.removeWhere((entry) => entry.sourcePath == session.sourcePath);
    _historyEntries.insert(0, updatedEntry);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _historyPreferenceKey,
      _historyEntries.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
    if (notify) {
      notifyListeners();
    }
  }
}

final databaseControllerProvider =
    ChangeNotifierProvider<DatabaseController>((ref) {
  return DatabaseController();
});