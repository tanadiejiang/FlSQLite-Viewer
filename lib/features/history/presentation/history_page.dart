import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../models/database_models.dart';
import '../../../state/database_controller.dart';

class HistoryPage extends ConsumerStatefulWidget {
  final Future<void> Function(DatabaseHistoryEntry entry) onOpenEntry;
  final String Function(FileAccessMode mode) modeLabelBuilder;

  const HistoryPage({
    super.key,
    required this.onOpenEntry,
    required this.modeLabelBuilder,
  });

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final Set<String> _selectedSourcePaths = <String>{};

  bool get _isSelectionMode => _selectedSourcePaths.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseControllerProvider);
    final theme = Theme.of(context);
    final s = context.strings;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelectionMode
              ? s.selectedCount(_selectedSourcePaths.length)
              : s.recentOpen,
        ),
        actions: [
          IconButton(
            icon: Icon(_isSelectionMode ? Icons.close : Icons.select_all),
            tooltip: _isSelectionMode ? s.exitSelection : s.multiSelect,
            onPressed: () {
              setState(_selectedSourcePaths.clear);
            },
          ),
          IconButton(
            icon: Icon(
              _isSelectionMode ? Icons.delete_outline : Icons.clear_all,
            ),
            tooltip: _isSelectionMode ? s.deleteSelected : s.clearRecords,
            onPressed: db.historyEntries.isEmpty
                ? null
                : () => _isSelectionMode
                    ? _deleteSelectedEntries()
                    : _clearAllHistory(),
          ),
        ],
      ),
      body: db.historyEntries.isEmpty
          ? Center(child: Text(s.noRecentRecords))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: db.historyEntries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = db.historyEntries[index];
                return _buildHistoryEntryTile(context, theme, entry);
              },
            ),
    );
  }

  Widget _buildHistoryEntryTile(
    BuildContext context,
    ThemeData theme,
    DatabaseHistoryEntry entry,
  ) {
    final isSelected = _selectedSourcePaths.contains(entry.sourcePath);
    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: isSelected ? Colors.lightBlue.withValues(alpha: 0.18) : null,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Card.outlined(
        color: isSelected ? Colors.transparent : null,
        child: ListTile(
          onTap: () async {
            if (_isSelectionMode) {
              _toggleSelection(entry.sourcePath);
              return;
            }
            await widget.onOpenEntry(entry);
          },
          onLongPress: () => _toggleSelection(entry.sourcePath),
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
          trailing: _HistoryMeta(
            modeLabel: widget.modeLabelBuilder(entry.accessMode),
            timeLabel: context.strings.formatRelativeTime(entry.lastOpenedAt),
            textTheme: theme.textTheme,
            colorScheme: theme.colorScheme,
          ),
        ),
      ),
    );

    if (_isSelectionMode) {
      return tile;
    }

    return Dismissible(
      key: ValueKey('history-${entry.sourcePath}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (_) async {
        await _deleteEntries([entry]);
        return false;
      },
      background: _buildDismissBackground(theme, Alignment.centerLeft),
      secondaryBackground: _buildDismissBackground(theme, Alignment.centerRight),
      child: tile,
    );
  }

  Widget _buildDismissBackground(ThemeData theme, Alignment alignment) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.error,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(Icons.delete_outline, color: Colors.white),
    );
  }

  void _toggleSelection(String sourcePath) {
    setState(() {
      if (_selectedSourcePaths.contains(sourcePath)) {
        _selectedSourcePaths.remove(sourcePath);
      } else {
        _selectedSourcePaths.add(sourcePath);
      }
    });
  }

  Future<void> _clearAllHistory() async {
    final s = context.strings;
    final confirmed = await _confirmAction(
      title: s.clearRecentTitle,
      content: s.clearRecentContent,
      actionText: s.clear,
    );
    if (confirmed != true || !mounted) {
      return;
    }

    await ref.read(databaseControllerProvider).clearHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.recentRecordsCleared)),
    );
  }

  Future<void> _deleteSelectedEntries() async {
    if (_selectedSourcePaths.isEmpty) {
      return;
    }
    final db = ref.read(databaseControllerProvider);
    final selectedEntries = db.historyEntries
        .where((entry) => _selectedSourcePaths.contains(entry.sourcePath))
        .toList();
    await _deleteEntries(selectedEntries);
  }

  Future<void> _deleteEntries(List<DatabaseHistoryEntry> entries) async {
    if (entries.isEmpty) {
      return;
    }

    final s = context.strings;
    final confirmed = await _confirmAction(
      title: s.deleteSelectedTitle(entries.length),
      content: s.deleteSelectedContent(
        entries.length,
        entries.first.displayName,
      ),
      actionText: s.delete,
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    await ref.read(databaseControllerProvider).removeHistoryEntries(
          entries.map((entry) => entry.sourcePath).toList(),
        );
    if (!mounted) return;
    setState(() {
      _selectedSourcePaths.removeAll(
        entries.map((entry) => entry.sourcePath),
      );
    });
    messenger.showSnackBar(
      SnackBar(content: Text(s.deletedRecentCount(entries.length))),
    );
  }

  Future<bool?> _confirmAction({
    required String title,
    required String content,
    required String actionText,
  }) {
    final s = context.strings;
    final errorColor = Theme.of(context).colorScheme.error;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: errorColor),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(actionText),
          ),
        ],
      ),
    );
  }
}

class _HistoryMeta extends StatelessWidget {
  final String modeLabel;
  final String timeLabel;
  final TextTheme textTheme;
  final ColorScheme colorScheme;

  const _HistoryMeta({
    required this.modeLabel,
    required this.timeLabel,
    required this.textTheme,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            modeLabel,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            timeLabel,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}