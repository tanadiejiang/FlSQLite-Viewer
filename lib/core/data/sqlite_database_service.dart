import 'package:sqlite3/sqlite3.dart';

import '../../models/database_models.dart';

/// Low-level SQLite access - open, PRAGMA, query, parameterized mutations.
class SqliteDatabaseService {
  Database? _db;
  String? _dbPath;

  Database get db {
    if (_db == null) throw StateError('No database opened');
    return _db!;
  }

  bool get isOpen => _db != null;
  String? get currentPath => _dbPath;

  /// Open a SQLite database file at [path].
  void open(String path) {
    close();
    _db = sqlite3.open(path);
    _dbPath = path;
    // Enable WAL recovery on open
    try {
      _db!.execute('PRAGMA journal_mode=WAL');
    } catch (_) {}
  }

  /// Close the current database.
  void close() {
    _db?.dispose();
    _db = null;
    _dbPath = null;
  }

  /// Re-open current database (useful after external changes).
  void reopen() {
    if (_dbPath == null) return;
    open(_dbPath!);
  }

  /// Get all tables and views from sqlite_master.
  List<String> getTableNames() {
    final result = db.select(
        "SELECT name FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY name");
    return result.map((r) => r['name'] as String).toList();
  }

  /// Get column info via PRAGMA table_info.
  List<TableColumnInfo> getTableColumns(String tableName) {
    final rows = db.select('PRAGMA table_info($tableName)');
    return rows.map((r) => TableColumnInfo.fromPragma(r)).toList();
  }

  /// Get full table schema (columns + info).
  DatabaseTable getTable(String tableName) {
    return DatabaseTable(
        name: tableName, columns: getTableColumns(tableName));
  }

  /// Count total rows in a table.
  int countRows(String tableName) {
    final result = db.select('SELECT COUNT(*) as cnt FROM $tableName');
    return result.first['cnt'] as int;
  }

  /// Query rows with optional filter and pagination.
  /// Returns [rows, totalCount].
  ({List<Map<String, dynamic>> rows, int total}) queryRows(
    String tableName,
    List<TableColumnInfo> columns, {
    int offset = 0,
    int limit = 100,
    String? searchTerm,
    String orderBy = 'rowid DESC',
  }) {
    final colNames = columns.map((c) => c.name).toList();
    var whereClause = '';
    var whereParams = <String>[];

    if (searchTerm != null && searchTerm.isNotEmpty) {
      final conditions = <String>[];
      for (final col in columns) {
        conditions.add("CAST(${col.name} AS TEXT) LIKE ?");
        whereParams.add('%$searchTerm%');
      }
      whereClause = 'WHERE ${conditions.join(' OR ')}';
    }

    final countSql =
        'SELECT COUNT(*) as cnt FROM $tableName $whereClause';
    final total = (db.select(countSql, whereParams).first['cnt'] as int?) ?? 0;

    final selectSql =
        'SELECT rowid, ${colNames.join(', ')} FROM $tableName $whereClause ORDER BY $orderBy LIMIT $limit OFFSET $offset';
    final rows = db.select(selectSql, whereParams);

    return (rows: rows, total: total);
  }

  /// Insert a new row. Returns the rowid of the inserted row.
  int insert(String tableName, Map<String, dynamic> values) {
    final sql =
        'INSERT INTO $tableName (${values.keys.join(', ')}) VALUES (${values.keys.map((_) => '?').join(', ')})';
    db.execute(sql, values.values.toList());
    return db.lastInsertRowId;
  }

  /// Update a row identified by [whereCol] = [whereVal].
  void update(String tableName, String whereCol, dynamic whereVal,
      Map<String, dynamic> values) {
    final sets =
        values.keys.map((k) => '$k = ?').join(', ');
    final sql = 'UPDATE $tableName SET $sets WHERE $whereCol = ?';
    final params = [...values.values, whereVal];
    db.execute(sql, params);
  }

  /// Delete a row identified by [whereCol] = [whereVal].
  void delete(String tableName, String whereCol, dynamic whereVal) {
    db.execute('DELETE FROM $tableName WHERE $whereCol = ?', [whereVal]);
  }

  /// Execute a raw SQL statement (for admin use).
  void executeRaw(String sql) {
    db.execute(sql);
  }
}