import '../../l10n/app_strings.dart';
import '../../models/database_models.dart';
import 'sqlite_database_service.dart';

/// High-level repository for SQLite operations.
/// Wraps SqliteDatabaseService with model transformations and safety checks.
class SqliteRepository {
  final SqliteDatabaseService _service;

  SqliteRepository(this._service);

  SqliteDatabaseService get service => _service;
  bool get isOpen => _service.isOpen;
  String? get currentPath => _service.currentPath;

  // --- Schema ---

  List<String> getTableNames() => _service.getTableNames();

  DatabaseTable getTable(String tableName) => _service.getTable(tableName);

  // --- Query ---

  TablePage queryPage(
    String tableName, {
    int page = 1,
    int pageSize = 50,
    String? searchTerm,
    String orderBy = 'rowid DESC',
  }) {
    final columns = _service.getTableColumns(tableName);
    final offset = (page - 1) * pageSize;
    final result = _service.queryRows(
      tableName,
      columns,
      offset: offset,
      limit: pageSize,
      searchTerm: searchTerm,
      orderBy: orderBy,
    );
    return TablePage(
      tableName: tableName,
      columns: columns,
      rows: result.rows,
      totalCount: result.total,
      pageSize: pageSize,
      currentPage: page,
    );
  }

  // --- Mutations ---

  int insertRow(String tableName, Map<String, dynamic> values) {
    return _service.insert(tableName, values);
  }

  /// Determine the best predicate set for locating a row.
  /// Prefer rowid from the current query result, then the full primary key set.
  Map<String, dynamic> _locateRow(
    String tableName,
    Map<String, dynamic> row,
  ) {
    if (row.containsKey('rowid')) {
      return {'rowid': row['rowid']};
    }

    final columns = _service.getTableColumns(tableName);
    final pks = columns.where((c) => c.primaryKey).toList();
    if (pks.isNotEmpty) {
      return {
        for (final pk in pks) pk.name: row[pk.name],
      };
    }

    throw StateError('Row locator unavailable for table $tableName');
  }

  void updateRow(
    String tableName,
    Map<String, dynamic> oldRow,
    Map<String, dynamic> newValues,
  ) {
    final locator = _locateRow(tableName, oldRow);
    final changed = <String, dynamic>{};
    for (final entry in newValues.entries) {
      if (entry.value != oldRow[entry.key]) {
        changed[entry.key] = entry.value;
      }
    }
    if (changed.isEmpty) return;

    final affected = _service.update(tableName, locator, changed);
    if (affected == 0) {
      throw StateError(AppStrings.current.rowNotFoundForUpdate);
    }
  }

  void deleteRow(String tableName, Map<String, dynamic> row) {
    final locator = _locateRow(tableName, row);
    final affected = _service.delete(tableName, locator);
    if (affected == 0) {
      throw StateError(AppStrings.current.rowNotFoundForDelete);
    }
  }

  // --- Lifecycle ---

  void open(String path) => _service.open(path);

  void close() => _service.close();

  void refresh() => _service.reopen();
}