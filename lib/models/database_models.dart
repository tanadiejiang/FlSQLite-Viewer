/// Data models for database schema, tables, columns, and paged rows.
class TableColumnInfo {
  final int cid;
  final String name;
  final String type;
  final bool notNull;
  final String? defaultValue;
  final bool primaryKey;

  const TableColumnInfo({
    required this.cid,
    required this.name,
    required this.type,
    required this.notNull,
    this.defaultValue,
    required this.primaryKey,
  });

  factory TableColumnInfo.fromPragma(Map<String, dynamic> row) => TableColumnInfo(
        cid: row['cid'] as int,
        name: row['name'] as String,
        type: (row['type'] as String?) ?? '',
        notNull: (row['notnull'] as int?) == 1,
        defaultValue: row['dflt_value'] as String?,
        primaryKey: (row['pk'] as int?) == 1,
      );

  Map<String, dynamic> toJson() => {
        'cid': cid,
        'name': name,
        'type': type,
        'notNull': notNull,
        'defaultValue': defaultValue,
        'primaryKey': primaryKey,
      };
}

class DatabaseTable {
  final String name;
  final List<TableColumnInfo> columns;

  const DatabaseTable({required this.name, required this.columns});

  List<String> get columnNames => columns.map((c) => c.name).toList();
  List<TableColumnInfo> get primaryKeys => columns.where((c) => c.primaryKey).toList();
}

class TablePage {
  final String tableName;
  final List<TableColumnInfo> columns;
  final List<Map<String, dynamic>> rows;
  final int totalCount;
  final int pageSize;
  final int currentPage;

  const TablePage({
    required this.tableName,
    required this.columns,
    required this.rows,
    required this.totalCount,
    required this.pageSize,
    required this.currentPage,
  });

  bool get hasMore => (currentPage * pageSize) < totalCount;
  int get totalPages => totalCount == 0 ? 0 : ((totalCount - 1) ~/ pageSize) + 1;
  int get offset => (currentPage - 1) * pageSize;
}

/// Android file access mode.
enum FileAccessMode { normal, manageAllFiles, root, shizuku }

String fileAccessModeName(FileAccessMode mode) => switch (mode) {
      FileAccessMode.normal => 'normal',
      FileAccessMode.manageAllFiles => 'manageAllFiles',
      FileAccessMode.root => 'root',
      FileAccessMode.shizuku => 'shizuku',
    };

FileAccessMode fileAccessModeFromName(String? value) => switch (value) {
      'manageAllFiles' => FileAccessMode.manageAllFiles,
      'root' => FileAccessMode.root,
      'shizuku' => FileAccessMode.shizuku,
      _ => FileAccessMode.normal,
    };

class DatabaseOpenSession {
  final String sourcePath;
  final String workPath;
  final FileAccessMode accessMode;
  final DateTime openedAt;

  const DatabaseOpenSession({
    required this.sourcePath,
    required this.workPath,
    required this.accessMode,
    required this.openedAt,
  });
}

class DatabaseHistoryEntry {
  final String sourcePath;
  final String displayName;
  final FileAccessMode accessMode;
  final DateTime lastOpenedAt;
  final String? lastTable;

  const DatabaseHistoryEntry({
    required this.sourcePath,
    required this.displayName,
    required this.accessMode,
    required this.lastOpenedAt,
    this.lastTable,
  });

  DatabaseHistoryEntry copyWith({
    String? sourcePath,
    String? displayName,
    FileAccessMode? accessMode,
    DateTime? lastOpenedAt,
    Object? lastTable = _historyNoChange,
  }) {
    return DatabaseHistoryEntry(
      sourcePath: sourcePath ?? this.sourcePath,
      displayName: displayName ?? this.displayName,
      accessMode: accessMode ?? this.accessMode,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      lastTable: identical(lastTable, _historyNoChange)
          ? this.lastTable
          : lastTable as String?,
    );
  }

  factory DatabaseHistoryEntry.fromJson(Map<String, dynamic> json) {
    return DatabaseHistoryEntry(
      sourcePath: json['sourcePath'] as String,
      displayName: json['displayName'] as String? ?? '',
      accessMode: fileAccessModeFromName(json['accessMode'] as String?),
      lastOpenedAt: DateTime.tryParse(json['lastOpenedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastTable: json['lastTable'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'sourcePath': sourcePath,
        'displayName': displayName,
        'accessMode': fileAccessModeName(accessMode),
        'lastOpenedAt': lastOpenedAt.toIso8601String(),
        'lastTable': lastTable,
      };
}

const _historyNoChange = Object();

/// Represents the state of a single Android advanced access capability.
class AccessCapability {
  final FileAccessMode mode;
  final bool enabled;
  final bool available;
  final String label;
  final String description;
  final String? statusText;
  final bool isChecking;

  const AccessCapability({
    required this.mode,
    this.enabled = false,
    this.available = false,
    required this.label,
    required this.description,
    this.statusText,
    this.isChecking = false,
  });

  AccessCapability copyWith({
    bool? enabled,
    bool? available,
    String? statusText,
    bool? isChecking,
  }) =>
      AccessCapability(
        mode: mode,
        enabled: enabled ?? this.enabled,
        available: available ?? this.available,
        label: label,
        description: description,
        statusText: statusText,
        isChecking: isChecking ?? this.isChecking,
      );
}

/// Directory entry from the internal file browser.
class DirectoryEntry {
  final String name;
  final bool isDirectory;
  final String fullPath;

  const DirectoryEntry({
    required this.name,
    required this.isDirectory,
    required this.fullPath,
  });
}