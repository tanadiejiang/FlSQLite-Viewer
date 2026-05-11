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

  /// Determine the best column and value for locating a row.
  /// Prefer primary keys, then rowid.
  ({String col, dynamic val}) _locateRow(
      String tableName, Map<String, dynamic> row) {
    final columns = _service.getTableColumns(tableName);
    final pks = columns.where((c) => c.primaryKey).toList();
    if (pks.isNotEmpty) {
      final pk = pks.first;
      return (col: pk.name, val: row[pk.name]);
    }
    // Fallback to rowid
    return (col: 'rowid', val: row['rowid']);
  }

  void updateRow(
      String tableName, Map<String, dynamic> oldRow, Map<String, dynamic> newValues) {
    final loc = _locateRow(tableName, oldRow);
    // Only update changed columns
    final changed = <String, dynamic>{};
    for (final entry in newValues.entries) {
      if (entry.value != oldRow[entry.key]) {
        changed[entry.key] = entry.value;
      }
    }
    if (changed.isEmpty) return;
    _service.update(tableName, loc.col, loc.val, changed);
  }

  void deleteRow(String tableName, Map<String, dynamic> row) {
    final loc = _locateRow(tableName, row);
    _service.delete(tableName, loc.col, loc.val);
  }

  // --- Lifecycle ---

  void open(String path) => _service.open(path);

  void close() => _service.close();

  void refresh() => _service.reopen();
}