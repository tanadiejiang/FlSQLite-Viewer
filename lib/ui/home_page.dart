import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/android_access/presentation/android_access_page.dart';
import '../features/database/presentation/data_grid.dart';
import '../features/database/presentation/row_detail_page.dart';
import '../features/database/presentation/row_editor_dialog.dart';
import '../features/file_browser/presentation/file_browser_page.dart';
import '../models/database_models.dart';
import '../state/database_controller.dart';
import '../state/file_access_controller.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseControllerProvider);
    final isAndroid = Platform.isAndroid;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('FlSQLite Viewer'),
        actions: [
          if (db.isOpen)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '关闭数据库',
              onPressed: () {
                db.closeDatabase();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('数据库已关闭')),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: '文件浏览器',
            onPressed: () => _openFileBrowser(context, ref),
          ),
          if (isAndroid)
            IconButton(
              icon: const Icon(Icons.shield_outlined),
              tooltip: '高级访问',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AndroidAccessPage(),
                  ),
                );
              },
            ),
          if (db.isOpen)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '新增行',
              onPressed: () => _showInsertDialog(context, ref),
            ),
        ],
      ),
      body: db.isOpen
          ? _buildDatabaseView(context, ref, db)
          : _buildWelcomeView(context, isAndroid, ref, db),
    );
  }

  Widget _buildWelcomeView(
    BuildContext context,
    bool isAndroid,
    WidgetRef ref,
    DatabaseController db,
  ) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storage, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'FlSQLite Viewer',
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '跨平台 SQLite 数据库查看与编辑器',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('打开数据库'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(220, 48),
              ),
              onPressed: () => _openFileBrowser(context, ref),
            ),
            if (isAndroid) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.shield_outlined),
                label: const Text('Android 高级访问设置'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AndroidAccessPage(),
                    ),
                  );
                },
              ),
            ],
            if (db.historyEntries.isNotEmpty) ...[
              const SizedBox(height: 24),
              Card.outlined(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '最近打开',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      for (final entry in db.historyEntries)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.history),
                          title: Text(
                            entry.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            entry.sourcePath,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            _modeLabel(entry.accessMode),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          onTap: () => _openRecentDatabase(context, ref, entry),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Card.outlined(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '支持的访问方式',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _featureRow(Icons.folder, '普通目录访问'),
                    _featureRow(Icons.folder_open, '全部文件访问'),
                    _featureRow(Icons.terminal, 'Root 模式 (su)'),
                    _featureRow(Icons.hub, 'Shizuku 授权访问'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
  }

  Widget _buildDatabaseView(
    BuildContext context,
    WidgetRef ref,
    DatabaseController db,
  ) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: theme.colorScheme.surfaceContainerLow,
          child: Row(
            children: [
              Icon(Icons.storage, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  db.currentPath ?? '',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final table in db.tableNames)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(table),
                      selected: db.currentTable == table,
                      onSelected: (_) => db.selectTable(table),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: DataGrid(
            onRefresh: () => db.refreshFromSource(
              ref.read(fileAccessControllerProvider),
            ),
            onOpenRowDetail: (row) => _openRowDetail(context, ref, row),
            onEditRow: (row) => _showEditDialog(context, ref, row),
            onDeleteRow: (row) => _confirmDelete(context, ref, row),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.save, size: 18),
            label: const Text('保存更改'),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('更改已自动保存到工作副本')),
              );
            },
          ),
        ),
      ],
    );
  }

  void _openFileBrowser(BuildContext context, WidgetRef ref) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FileBrowserPage(
          onDatabaseSelected: (path, forcedMode) async {
            Navigator.of(context).pop();
            final access = ref.read(fileAccessControllerProvider);
            final db = ref.read(databaseControllerProvider);
            try {
              final session = await access.openDatabaseFile(
                path,
                forcedMode: forcedMode,
              );
              await db.openDatabase(session);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已打开: $path')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_formatOpenFailureMessage(e))),
                );
              }
            }
          },
        ),
      ),
    );
  }

  Future<void> _openRecentDatabase(
    BuildContext context,
    WidgetRef ref,
    DatabaseHistoryEntry entry,
  ) async {
    final access = ref.read(fileAccessControllerProvider);
    final db = ref.read(databaseControllerProvider);
    try {
      final session = await access.openDatabaseFile(
        entry.sourcePath,
        forcedMode:
            entry.accessMode == FileAccessMode.normal ? null : entry.accessMode,
      );
      await db.openDatabase(session, preferredTable: entry.lastTable);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已重新打开: ${entry.displayName}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_formatOpenFailureMessage(e))),
        );
      }
    }
  }

  void _openRowDetail(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> row,
  ) {
    final db = ref.read(databaseControllerProvider);
    if (db.tableSchema == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RowDetailPage(
          table: db.tableSchema!,
          row: row,
          onSave: (values) {
            db.updateRow(row, values);
          },
        ),
      ),
    );
  }

  void _showInsertDialog(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseControllerProvider);
    if (db.currentTable == null || db.tableSchema == null) return;

    showDialog(
      context: context,
      builder: (ctx) => RowEditorDialog(table: db.tableSchema!),
    ).then((values) {
      if (values is Map<String, dynamic> && context.mounted) {
        db.insertRow(values);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已新增行')));
      }
    });
  }

  void _showEditDialog(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> row,
  ) {
    final db = ref.read(databaseControllerProvider);
    if (db.tableSchema == null) return;

    showDialog(
      context: context,
      builder: (ctx) => RowEditorDialog(
        table: db.tableSchema!,
        existingRow: row,
        isEdit: true,
      ),
    ).then((values) {
      if (values is Map<String, dynamic> && context.mounted) {
        db.updateRow(row, values);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已更新行')));
      }
    });
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> row,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这行数据吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              final db = ref.read(databaseControllerProvider);
              db.deleteRow(row);
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('已删除行')));
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  String _formatOpenFailureMessage(Object error) {
    if (error is AccessModeUnavailableException) {
      return error.message;
    }
    if (error is FileAccessFailureException) {
      return error.summary;
    }
    return '打开失败: $error';
  }

  String _modeLabel(FileAccessMode mode) {
    switch (mode) {
      case FileAccessMode.manageAllFiles:
        return '全部文件';
      case FileAccessMode.root:
        return 'Root';
      case FileAccessMode.shizuku:
        return 'Shizuku';
      case FileAccessMode.normal:
        return '普通';
    }
  }
}