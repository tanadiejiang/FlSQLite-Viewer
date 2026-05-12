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

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with SingleTickerProviderStateMixin {
  static const double _tableSelectorExpandedHeight = 44;
  static const double _tableSelectorCollapseRange = 96;
  static const double _tableSelectorRevealLeadDistance = 192;
  static const double _tableSelectorRevealDistance = 128;
  static const double _tableSelectorTopPullRevealDistance = 160;
  static const double _tableSelectorAutoCollapseThreshold = 0.25;
  static const double _tableSelectorAutoExpandThreshold = 0.8;

  double _tableSelectorCollapseProgress = 0;
  double? _lastTableScrollOffset;
  double _tableSelectorRevealAccumulator = 0;
  double? _topPullStartProgress;
  bool _lastScrollWasReveal = false;
  late final AnimationController _tableSelectorSettleController;
  Animation<double>? _tableSelectorSettleAnimation;

  @override
  void initState() {
    super.initState();
    _tableSelectorSettleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        final animation = _tableSelectorSettleAnimation;
        if (animation == null || !mounted) {
          return;
        }
        setState(() {
          _tableSelectorCollapseProgress = animation.value;
        });
      });
  }

  @override
  void dispose() {
    _tableSelectorSettleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseControllerProvider);
    final isAndroid = Platform.isAndroid;

    return PopScope(
      canPop: !db.isOpen,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !db.isOpen) {
          return;
        }
        await _handleBackFromDatabase(context, db);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          leading: db.isOpen
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '返回',
                  onPressed: () => _handleBackFromDatabase(context, db),
                )
              : null,
          automaticallyImplyLeading: false,
          title: db.isOpen ? null : const Text('FlSQLite Viewer'),
          actions: [
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: '文件浏览器',
              onPressed: () => _openFileBrowser(context),
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
                onPressed: () => _showInsertDialog(context),
              ),
          ],
        ),
        body: db.isOpen
            ? _buildDatabaseView(context, db)
            : _buildWelcomeView(context, isAndroid, db),
      ),
    );
  }

  Widget _buildWelcomeView(
    BuildContext context,
    bool isAndroid,
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
              onPressed: () => _openFileBrowser(context),
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
                          onTap: () => _openRecentDatabase(context, entry),
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

  Widget _buildDatabaseView(BuildContext context, DatabaseController db) {
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
        SizedBox(
          width: double.infinity,
          height:
              _tableSelectorExpandedHeight * (1 - _tableSelectorCollapseProgress),
          child: ClipRect(
            child: Align(
              alignment: Alignment.topLeft,
              heightFactor: 1 - _tableSelectorCollapseProgress,
              child: Opacity(
                opacity: 1 - _tableSelectorCollapseProgress,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
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
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: DataGrid(
            hasUnsavedChanges: db.hasUnsavedChanges,
            isSaving: db.isSaving,
            onSaveChanges: () => _saveChanges(db),
            onVerticalScroll: _handleTableSelectorScroll,
            onVerticalScrollEnd: _handleTableSelectorScrollEnd,
            onRefresh: () => db.refreshFromSource(
              ref.read(fileAccessControllerProvider),
            ),
            onOpenRowDetail: (row) => _openRowDetail(context, row),
            onEditRow: (row) => _showEditDialog(context, row),
            onDeleteRow: (row) => _confirmDelete(context, row),
          ),
        ),
      ],
    );
  }

  void _resetTableSelectorScrollState() {
    _tableSelectorCollapseProgress = 0;
    _tableSelectorRevealAccumulator = 0;
    _lastTableScrollOffset = null;
    _topPullStartProgress = null;
    _lastScrollWasReveal = false;
    _tableSelectorSettleAnimation = null;
    _tableSelectorSettleController.stop();
  }

  void _stopTableSelectorSettleAnimation() {
    if (_tableSelectorSettleController.isAnimating) {
      _tableSelectorSettleController.stop();
    }
    _tableSelectorSettleAnimation = null;
  }

  void _animateTableSelectorProgressTo(double target) {
    _stopTableSelectorSettleAnimation();
    _tableSelectorSettleAnimation = Tween<double>(
      begin: _tableSelectorCollapseProgress,
      end: target,
    ).animate(
      CurvedAnimation(
        parent: _tableSelectorSettleController,
        curve: Curves.easeOutCubic,
      ),
    );
    _tableSelectorSettleController
      ..reset()
      ..forward();
  }

  void _handleTableSelectorScrollEnd() {
    _topPullStartProgress = null;
    if (_lastScrollWasReveal &&
        _tableSelectorCollapseProgress > 0 &&
        _tableSelectorCollapseProgress <= _tableSelectorAutoExpandThreshold) {
      _animateTableSelectorProgressTo(0);
    } else if (!_lastScrollWasReveal &&
        _tableSelectorCollapseProgress >= _tableSelectorAutoCollapseThreshold &&
        _tableSelectorCollapseProgress < 1) {
      _animateTableSelectorProgressTo(1);
    }
    _lastScrollWasReveal = false;
  }

  void _handleTableSelectorScroll(double offset) {
    _stopTableSelectorSettleAnimation();
    final previousOffset = _lastTableScrollOffset;
    _lastTableScrollOffset = offset;
    if (previousOffset == null) {
      return;
    }

    if (previousOffset >= 0 && offset < 0) {
      _topPullStartProgress = _tableSelectorCollapseProgress;
    }

    if (previousOffset < 0 && offset >= 0) {
      _lastTableScrollOffset = 0;
      _topPullStartProgress = null;
      return;
    }

    if (offset < 0 || previousOffset < 0) {
      final topPullDistance = offset < 0 ? -offset : 0.0;
      final startProgress = _topPullStartProgress ?? _tableSelectorCollapseProgress;
      final nextProgress =
          (startProgress - topPullDistance / _tableSelectorTopPullRevealDistance)
              .clamp(0.0, 1.0);
      _tableSelectorRevealAccumulator = 0;
      _lastScrollWasReveal = nextProgress < _tableSelectorCollapseProgress;
      if ((nextProgress - _tableSelectorCollapseProgress).abs() > 0.001 &&
          mounted) {
        setState(() {
          _tableSelectorCollapseProgress = nextProgress;
        });
      }
      return;
    }

    final delta = offset - previousOffset;
    if (delta.abs() < 0.5) {
      return;
    }

    var nextProgress = _tableSelectorCollapseProgress;
    if (delta > 0) {
      _tableSelectorRevealAccumulator = 0;
      nextProgress =
          (nextProgress + delta / _tableSelectorCollapseRange).clamp(0.0, 1.0);
    } else {
      final upwardDistance = -delta;
      if (nextProgress >= 0.999 || _tableSelectorRevealAccumulator > 0) {
        _tableSelectorRevealAccumulator += upwardDistance;
        if (_tableSelectorRevealAccumulator <=
            _tableSelectorRevealLeadDistance) {
          nextProgress = 1.0;
        } else {
          final revealProgress = ((_tableSelectorRevealAccumulator -
                      _tableSelectorRevealLeadDistance) /
                  _tableSelectorRevealDistance)
              .clamp(0.0, 1.0);
          nextProgress = 1.0 - revealProgress;
        }
      } else {
        nextProgress =
            (nextProgress - upwardDistance / _tableSelectorRevealDistance)
                .clamp(0.0, 1.0);
      }
    }

    if (nextProgress <= 0.001) {
      _tableSelectorRevealAccumulator = 0;
      nextProgress = 0;
    }

    _lastScrollWasReveal = nextProgress < _tableSelectorCollapseProgress;
    if ((nextProgress - _tableSelectorCollapseProgress).abs() > 0.001 &&
        mounted) {
      setState(() {
        _tableSelectorCollapseProgress = nextProgress;
      });
    }
  }

  Future<void> _saveChanges(DatabaseController db) async {
    final messenger = ScaffoldMessenger.of(context);
    final access = ref.read(fileAccessControllerProvider);
    await db.saveChanges(access);
    if (!mounted) return;
    if (db.errorMessage != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(db.errorMessage!)),
      );
      return;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('更改已保存到源文件')),
    );
  }

  Future<void> _handleBackFromDatabase(
    BuildContext context,
    DatabaseController db,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!db.hasUnsavedChanges) {
      db.closeDatabase();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('数据库已关闭')),
        );
      }
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('有未保存修改'),
        content: const Text('是否先保存当前修改再返回？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('discard'),
            child: const Text('不保存'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('save'),
            child: const Text('保存并返回'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (action == 'save') {
      await _saveChanges(db);
      if (!mounted) return;
      if (db.errorMessage != null || db.hasUnsavedChanges) {
        return;
      }
      db.closeDatabase();
      messenger.showSnackBar(
        const SnackBar(content: Text('数据库已关闭')),
      );
    } else if (action == 'discard') {
      db.closeDatabase();
      messenger.showSnackBar(
        const SnackBar(content: Text('已放弃未保存修改')),
      );
    }
  }

  void _openFileBrowser(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
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
              if (!mounted) return;
              setState(_resetTableSelectorScrollState);
              messenger.showSnackBar(
                SnackBar(content: Text('已打开: $path')),
              );
            } catch (e) {
              if (!mounted) return;
              messenger.showSnackBar(
                SnackBar(content: Text(_formatOpenFailureMessage(e))),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _openRecentDatabase(
    BuildContext context,
    DatabaseHistoryEntry entry,
  ) async {
    final access = ref.read(fileAccessControllerProvider);
    final db = ref.read(databaseControllerProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final session = await access.openDatabaseFile(
        entry.sourcePath,
        forcedMode:
            entry.accessMode == FileAccessMode.normal ? null : entry.accessMode,
      );
      await db.openDatabase(session, preferredTable: entry.lastTable);
      if (!mounted) return;
      setState(_resetTableSelectorScrollState);
      messenger.showSnackBar(
        SnackBar(content: Text('已重新打开: ${entry.displayName}')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(_formatOpenFailureMessage(e))),
      );
    }
  }

  void _openRowDetail(
    BuildContext context,
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

  void _showInsertDialog(BuildContext context) {
    final db = ref.read(databaseControllerProvider);
    if (db.currentTable == null || db.tableSchema == null) return;

    showDialog(
      context: context,
      builder: (ctx) => RowEditorDialog(table: db.tableSchema!),
    ).then((values) {
      if (values is Map<String, dynamic> && context.mounted) {
        db.insertRow(values);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已新增行，待保存到源文件')));
      }
    });
  }

  void _showEditDialog(
    BuildContext context,
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
            .showSnackBar(const SnackBar(content: Text('已更新行，待保存到源文件')));
      }
    });
  }

  void _confirmDelete(
    BuildContext context,
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已删除行，待保存到源文件')),
              );
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