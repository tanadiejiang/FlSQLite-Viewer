import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/android_access/presentation/android_access_page.dart';
import '../features/database/presentation/data_grid.dart';
import '../features/database/presentation/row_detail_page.dart';
import '../features/database/presentation/row_editor_dialog.dart';
import '../features/file_browser/presentation/file_browser_page.dart';
import '../features/history/presentation/history_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../l10n/app_strings.dart';
import '../models/database_models.dart';
import '../state/database_controller.dart';
import '../state/file_access_controller.dart';

class HomePage extends ConsumerStatefulWidget {
  final List<String> initialOpenPaths;

  const HomePage({super.key, this.initialOpenPaths = const []});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with SingleTickerProviderStateMixin {
  static const _desktopOpenChannel = MethodChannel(
    'lingxue.flsqliteviewer/desktop_open',
  );
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
    Future.microtask(() async {
      final access = ref.read(fileAccessControllerProvider);
      await access.ensureInitialized();
      await access.checkAllStatuses(forceRefresh: true);
      if (!mounted) return;
      for (final path in widget.initialOpenPaths) {
        final opened = await _openDatabasePath(path, showSuccess: false);
        if (opened) {
          break;
        }
      }
    });
    _desktopOpenChannel.setMethodCallHandler(_handleDesktopOpenCall);
    _tableSelectorSettleController =
        AnimationController(
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
    _desktopOpenChannel.setMethodCallHandler(null);
    _tableSelectorSettleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseControllerProvider);
    final isAndroid = Platform.isAndroid;
    final s = context.strings;

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
                  tooltip: s.back,
                  onPressed: () => _handleBackFromDatabase(context, db),
                )
              : IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: s.settings,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    );
                  },
                ),
          automaticallyImplyLeading: false,
          title: null,
          actions: [
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: s.fileBrowser,
              onPressed: () => _openFileBrowser(context),
            ),
            if (isAndroid)
              IconButton(
                icon: const Icon(Icons.shield_outlined),
                tooltip: s.advancedAccess,
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
                tooltip: s.addRow,
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
    final s = context.strings;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storage, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              s.appName,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.homeSubtitle,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.folder_open),
              label: Text(s.openDatabase),
              style: FilledButton.styleFrom(minimumSize: const Size(220, 48)),
              onPressed: () => _openFileBrowser(context),
            ),
            if (isAndroid) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.shield_outlined),
                label: Text(s.androidAdvancedAccessSettings),
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
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openHistoryPage(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  s.recentOpen,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final entry in db.historyEntries.take(4))
                        _buildRecentHistoryTile(context, theme, entry),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Card.outlined(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: isAndroid
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.supportedAccessTypes,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _featureRow(Icons.folder, s.normalDirectoryAccess),
                          _featureRow(Icons.folder_open, s.allFilesAccess),
                          _featureRow(Icons.terminal, s.rootMode),
                          _featureRow(Icons.hub, s.shizukuAccess),
                        ],
                      )
                    : Row(
                        children: [
                          Icon(
                            Icons.upload_file_outlined,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            s.desktopOpenHint,
                            style: theme.textTheme.bodyMedium,
                          ),
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
        children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(text)],
      ),
    );
  }

  Widget _buildRecentHistoryTile(
    BuildContext context,
    ThemeData theme,
    DatabaseHistoryEntry entry,
  ) {
    return Dismissible(
      key: ValueKey('recent-${entry.sourcePath}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (_) async {
        await _confirmDeleteHistoryEntry(context, entry);
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: ListTile(
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
        trailing: _buildHistoryMeta(
          theme,
          modeLabel: _modeLabel(entry.accessMode),
          timeLabel: _formatHistoryTime(context, entry.lastOpenedAt),
        ),
        onTap: () => _openRecentDatabase(context, entry),
        onLongPress: () => _confirmDeleteHistoryEntry(context, entry),
      ),
    );
  }

  Widget _buildHistoryMeta(
    ThemeData theme, {
    required String modeLabel,
    required String timeLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            modeLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            timeLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _formatHistoryTime(BuildContext context, DateTime value) {
    return context.strings.formatRelativeTime(value);
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
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
              _tableSelectorExpandedHeight *
              (1 - _tableSelectorCollapseProgress),
          child: ClipRect(
            child: Align(
              alignment: Alignment.topLeft,
              heightFactor: 1 - _tableSelectorCollapseProgress,
              child: Opacity(
                opacity: 1 - _tableSelectorCollapseProgress,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
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
                                onSelected: (_) {
                                  setState(_resetTableSelectorScrollState);
                                  db.selectTable(table);
                                },
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
            onRefresh: () =>
                db.refreshFromSource(ref.read(fileAccessControllerProvider)),
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
    _tableSelectorSettleAnimation =
        Tween<double>(
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
      final startProgress =
          _topPullStartProgress ?? _tableSelectorCollapseProgress;
      final nextProgress =
          (startProgress -
                  topPullDistance / _tableSelectorTopPullRevealDistance)
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
      nextProgress = (nextProgress + delta / _tableSelectorCollapseRange).clamp(
        0.0,
        1.0,
      );
    } else {
      final upwardDistance = -delta;
      if (nextProgress >= 0.999 || _tableSelectorRevealAccumulator > 0) {
        _tableSelectorRevealAccumulator += upwardDistance;
        if (_tableSelectorRevealAccumulator <=
            _tableSelectorRevealLeadDistance) {
          nextProgress = 1.0;
        } else {
          final revealProgress =
              ((_tableSelectorRevealAccumulator -
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

  Future<bool> _saveChanges(DatabaseController db) async {
    final messenger = ScaffoldMessenger.of(context);
    final access = ref.read(fileAccessControllerProvider);
    final s = context.strings;
    await db.saveChanges(access);
    if (!mounted) return false;
    if (db.errorMessage != null) {
      messenger.showSnackBar(SnackBar(content: Text(db.errorMessage!)));
      return false;
    }
    messenger.showSnackBar(SnackBar(content: Text(s.changesSavedToSource)));
    return !db.hasUnsavedChanges;
  }

  Future<void> _handleBackFromDatabase(
    BuildContext context,
    DatabaseController db,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final s = context.strings;
    if (!db.hasUnsavedChanges) {
      db.closeDatabase();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(s.databaseClosed)));
      }
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.unsavedChangesTitle),
        content: Text(s.unsavedChangesContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('discard'),
            child: Text(s.discard),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('save'),
            child: Text(s.saveAndBack),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (action == 'save') {
      final saved = await _saveChanges(db);
      if (!mounted) return;
      if (!saved || db.errorMessage != null || db.hasUnsavedChanges) {
        return;
      }
      db.closeDatabase();
      messenger.showSnackBar(SnackBar(content: Text(s.databaseClosed)));
    } else if (action == 'discard') {
      db.closeDatabase();
      messenger.showSnackBar(
        SnackBar(content: Text(s.discardedUnsavedChanges)),
      );
    }
  }

  Future<dynamic> _handleDesktopOpenCall(MethodCall call) async {
    if (call.method != 'openFiles') {
      return null;
    }
    final paths =
        (call.arguments as List?)
            ?.whereType<String>()
            .where((path) => path.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    for (final path in paths) {
      final opened = await _openDatabasePath(path);
      if (opened) {
        break;
      }
    }
    return null;
  }

  Future<bool> _confirmUnsavedBeforeOpening(DatabaseController db) async {
    if (!db.isOpen || !db.hasUnsavedChanges) {
      return true;
    }
    final s = context.strings;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.unsavedChangesTitle),
        content: Text(s.saveBeforeOpenNewFileContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('cancel'),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('discard'),
            child: Text(s.no),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('save'),
            child: Text(s.yes),
          ),
        ],
      ),
    );
    if (!mounted) {
      return false;
    }
    if (action == 'save') {
      return _saveChanges(db);
    }
    if (action == 'discard') {
      db.closeDatabase();
      return true;
    }
    return false;
  }

  Future<bool> _openDatabasePath(
    String path, {
    FileAccessMode? forcedMode,
    bool showSuccess = true,
  }) async {
    if (!mounted) {
      return false;
    }
    final messenger = ScaffoldMessenger.of(context);
    final s = context.strings;
    final access = ref.read(fileAccessControllerProvider);
    final db = ref.read(databaseControllerProvider);
    try {
      final canOpen = await _confirmUnsavedBeforeOpening(db);
      if (!canOpen || !mounted) {
        return false;
      }
      final session = await access.openDatabaseFile(
        path,
        forcedMode: forcedMode,
      );
      await db.openDatabase(session);
      if (!mounted) return true;
      setState(_resetTableSelectorScrollState);
      if (showSuccess) {
        messenger.showSnackBar(SnackBar(content: Text(s.openedPath(path))));
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      messenger.showSnackBar(
        SnackBar(content: Text(_formatOpenFailureMessage(e))),
      );
      return false;
    }
  }

  void _openFileBrowser(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FileBrowserPage(
          onDatabaseSelected: (path, forcedMode) async {
            Navigator.of(context).pop();
            await _openDatabasePath(path, forcedMode: forcedMode);
          },
        ),
      ),
    );
  }

  Future<void> _openHistoryPage(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageContext) => HistoryPage(
          onOpenEntry: (entry) async {
            Navigator.of(pageContext).pop();
            await _openRecentDatabase(context, entry);
          },
          modeLabelBuilder: _modeLabel,
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
      final canOpen = await _confirmUnsavedBeforeOpening(db);
      if (!canOpen || !context.mounted) {
        return;
      }
      await access.ensureInitialized();
      await access.checkAllStatuses(forceRefresh: true);
      final session = await access.openDatabaseFile(
        entry.sourcePath,
        forcedMode: entry.accessMode == FileAccessMode.normal
            ? null
            : entry.accessMode,
      );
      await db.openDatabase(session, preferredTable: entry.lastTable);
      if (!context.mounted) return;
      setState(_resetTableSelectorScrollState);
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.strings.reopenedName(entry.displayName)),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(_formatOpenFailureMessage(e))),
      );
    }
  }

  Future<void> _confirmDeleteHistoryEntry(
    BuildContext context,
    DatabaseHistoryEntry entry,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final s = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.recentDeleteTitle),
        content: Text(s.deleteRecentContent(entry.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: errorColor),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final db = ref.read(databaseControllerProvider);
    await db.removeHistoryEntry(entry.sourcePath);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(s.deletedRecent(entry.displayName))),
    );
  }

  void _openRowDetail(BuildContext context, Map<String, dynamic> row) {
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
          onDelete: (targetRow) {
            db.deleteRow(targetRow);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.rowAddedPendingSave)),
        );
      }
    });
  }

  void _showEditDialog(BuildContext context, Map<String, dynamic> row) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.rowUpdatedPendingSave)),
        );
      }
    });
  }

  void _confirmDelete(BuildContext context, Map<String, dynamic> row) {
    final s = context.strings;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.confirmDelete),
        content: Text(s.confirmDeleteRowContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              final db = ref.read(databaseControllerProvider);
              db.deleteRow(row);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(s.rowDeletedPendingSave)));
            },
            child: Text(s.delete),
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
    return context.strings.openFailed(error);
  }

  String _modeLabel(FileAccessMode mode) {
    final s = context.strings;
    switch (mode) {
      case FileAccessMode.manageAllFiles:
        return s.modeAllFiles;
      case FileAccessMode.root:
        return s.modeRoot;
      case FileAccessMode.shizuku:
        return s.modeShizuku;
      case FileAccessMode.normal:
        return s.modeNormal;
    }
  }
}
