import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/database_models.dart';
import '../../../state/database_controller.dart';

class DataGrid extends ConsumerStatefulWidget {
  final Future<void> Function()? onRefresh;
  final Future<void> Function()? onSaveChanges;
  final bool hasUnsavedChanges;
  final bool isSaving;
  final ValueChanged<double>? onVerticalScroll;
  final VoidCallback? onVerticalScrollEnd;
  final ValueChanged<Map<String, dynamic>>? onOpenRowDetail;
  final ValueChanged<Map<String, dynamic>>? onEditRow;
  final ValueChanged<Map<String, dynamic>>? onDeleteRow;

  const DataGrid({
    super.key,
    this.onRefresh,
    this.onSaveChanges,
    this.hasUnsavedChanges = false,
    this.isSaving = false,
    this.onVerticalScroll,
    this.onVerticalScrollEnd,
    this.onOpenRowDetail,
    this.onEditRow,
    this.onDeleteRow,
  });

  @override
  ConsumerState<DataGrid> createState() => _DataGridState();
}

class _DataGridState extends ConsumerState<DataGrid> {
  static const double _indexColumnWidth = 88;
  static const double _dataColumnWidth = 240;
  static const double _minDataColumnWidth = 140;
  static const double _maxDataColumnWidth = 520;
  static const double _actionColumnWidth = 152;
  static const double _headerHeight = 48;
  static const double _rowHeight = 64;

  final _searchController = TextEditingController();
  final _verticalController = ScrollController();
  final _horizontalController = ScrollController();
  final Map<String, double> _columnWidths = {};
  double _topOverscrollExtent = 0;

  String? _resizingColumn;
  double _resizeStartDx = 0;
  double _resizeStartWidth = _dataColumnWidth;

  @override
  void initState() {
    super.initState();
    _verticalController.addListener(_handleVerticalScroll);
  }

  @override
  void dispose() {
    _verticalController.removeListener(_handleVerticalScroll);
    _searchController.dispose();
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseControllerProvider);
    final theme = Theme.of(context);
    final page = db.currentPage;

    final searchText = db.searchTerm ?? '';
    if (_searchController.text != searchText) {
      _searchController.value = TextEditingValue(
        text: searchText,
        selection: TextSelection.collapsed(offset: searchText.length),
      );
    }

    if (!db.isOpen) {
      return const Center(child: Text('未打开数据库'));
    }

    if (db.currentTable == null) {
      return const Center(child: Text('未选择表'));
    }

    if (db.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (db.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.red),
            const SizedBox(height: 8),
            Text(
              db.errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _handleRefresh(db),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (page == null || page.rows.isEmpty) {
      return Column(
        children: [
          _buildSearchBar(context, db),
          const Expanded(child: Center(child: Text('无数据'))),
          _buildPaginationBar(context, db, page),
        ],
      );
    }

    final columns = page.columns;
    _ensureColumnWidths(columns);

    return Column(
      children: [
        _buildSearchBar(context, db),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Text(
                '${page.offset + 1}-${(page.offset + page.rows.length).clamp(0, page.totalCount)} / ${page.totalCount} 行',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                '第 ${page.currentPage}/${page.totalPages} 页',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = _tableWidth(columns);
              final viewportWidth =
                  contentWidth < constraints.maxWidth ? constraints.maxWidth : contentWidth;
              return SingleChildScrollView(
                controller: _horizontalController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: viewportWidth,
                  height: constraints.maxHeight,
                  child: Column(
                    children: [
                      _buildHeaderRow(context, theme, columns),
                      const Divider(height: 1),
                      Expanded(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _handleScrollNotification,
                          child: ListView.separated(
                            controller: _verticalController,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemCount: page.rows.length,
                            separatorBuilder: (_, separatorIndex) => Divider(
                              height: 1,
                              thickness: 0.6,
                              color: theme.dividerColor.withValues(alpha: 0.4),
                            ),
                            itemBuilder: (context, index) {
                              final row = page.rows[index];
                              return _buildDataRow(context, theme, columns, row);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _buildPaginationBar(context, db, page),
      ],
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (widget.onVerticalScroll == null) {
      return false;
    }

    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      if (notification.metrics.pixels >= 0 && _topOverscrollExtent != 0) {
        _topOverscrollExtent = 0;
      }
      widget.onVerticalScroll!(notification.metrics.pixels - _topOverscrollExtent);
    } else if (notification is OverscrollNotification) {
      if (notification.metrics.pixels <= notification.metrics.minScrollExtent &&
          notification.overscroll < 0) {
        _topOverscrollExtent =
            (_topOverscrollExtent + (-notification.overscroll)).clamp(0.0, double.infinity);
        widget.onVerticalScroll!(-_topOverscrollExtent);
      }
    } else if (notification is ScrollEndNotification &&
        notification.metrics.pixels >= 0 &&
        _topOverscrollExtent != 0) {
      _topOverscrollExtent = 0;
      widget.onVerticalScroll!(notification.metrics.pixels);
      widget.onVerticalScrollEnd?.call();
    } else if (notification is ScrollEndNotification) {
      widget.onVerticalScrollEnd?.call();
    }

    return false;
  }

  void _handleVerticalScroll() {
    widget.onVerticalScroll?.call(_verticalController.offset);
  }

  Widget _buildSearchBar(BuildContext context, DatabaseController db) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          FilledButton.tonalIcon(
            onPressed: widget.hasUnsavedChanges && !widget.isSaving
                ? () => widget.onSaveChanges?.call()
                : null,
            icon: widget.isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save, size: 18),
            label: Text(widget.isSaving ? '保存中' : '保存'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索 ${db.currentTable}...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: db.searchTerm != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          db.setSearch(null);
                        },
                      )
                    : null,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) => db.setSearch(v),
            ),
          ),
        ],
      ),
    );
  }

  void _ensureColumnWidths(List<TableColumnInfo> columns) {
    for (final column in columns) {
      _columnWidths.putIfAbsent(column.name, () => _dataColumnWidth);
    }
    if (_resizingColumn != null &&
        columns.every((column) => column.name != _resizingColumn)) {
      _resizingColumn = null;
    }
  }

  double _columnWidthFor(String columnName) {
    return _columnWidths[columnName] ?? _dataColumnWidth;
  }

  double _tableWidth(List<TableColumnInfo> columns) {
    return _indexColumnWidth +
        _actionColumnWidth +
        columns.fold<double>(0, (sum, column) => sum + _columnWidthFor(column.name));
  }

  Widget _buildHeaderRow(
    BuildContext context,
    ThemeData theme,
    List<TableColumnInfo> columns,
  ) {
    final color = theme.colorScheme.surfaceContainerHighest;
    return Container(
      height: _headerHeight,
      color: color,
      child: Row(
        children: [
          _buildHeaderCell('#', width: _indexColumnWidth),
          for (final col in columns)
            _buildResizableHeaderCell(context, theme, col),
          _buildHeaderCell('操作', width: _actionColumnWidth, alignEnd: true),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(
    String text, {
    required double width,
    bool alignEnd = false,
  }) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildResizableHeaderCell(
    BuildContext context,
    ThemeData theme,
    TableColumnInfo column,
  ) {
    final width = _columnWidthFor(column.name);
    final isResizing = _resizingColumn == column.name;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (details) {
        setState(() {
          _resizingColumn = column.name;
          _resizeStartDx = details.globalPosition.dx;
          _resizeStartWidth = _columnWidthFor(column.name);
        });
      },
      onLongPressMoveUpdate: (details) {
        if (_resizingColumn != column.name) return;
        final delta = details.globalPosition.dx - _resizeStartDx;
        final nextWidth = (_resizeStartWidth + delta).clamp(
          _minDataColumnWidth,
          _maxDataColumnWidth,
        );
        setState(() {
          _columnWidths[column.name] = nextWidth;
        });
      },
      onLongPressEnd: (_) {
        if (_resizingColumn == column.name) {
          setState(() {
            _resizingColumn = null;
          });
        }
      },
      child: Container(
        width: width,
        height: _headerHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: isResizing
              ? Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                column.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.drag_indicator,
              size: 14,
              color: isResizing
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(
    BuildContext context,
    ThemeData theme,
    List<TableColumnInfo> columns,
    Map<String, dynamic> row,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onLongPress: widget.onOpenRowDetail == null
            ? null
            : () => widget.onOpenRowDetail?.call(row),
        child: SizedBox(
          height: _rowHeight,
          child: Row(
            children: [
              _buildValueCell(
                text: '${row['rowid'] ?? ''}',
                width: _indexColumnWidth,
                bold: true,
              ),
              for (final col in columns)
                _buildValueCell(
                  text: '${row[col.name] ?? ''}',
                  width: _columnWidthFor(col.name),
                ),
              _buildActionCell(theme, row),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildValueCell({
    required String text,
    required double width,
    bool bold = false,
  }) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionCell(ThemeData theme, Map<String, dynamic> row) {
    return SizedBox(
      width: _actionColumnWidth,
      child: Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.visibility_outlined, size: 18),
              tooltip: '详情',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              onPressed: widget.onOpenRowDetail == null
                  ? null
                  : () => widget.onOpenRowDetail?.call(row),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: widget.onEditRow == null
                  ? null
                  : () => widget.onEditRow?.call(row),
              tooltip: '编辑',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            ),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: theme.colorScheme.error,
              ),
              onPressed: widget.onDeleteRow == null
                  ? null
                  : () => widget.onDeleteRow?.call(row),
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaginationBar(
    BuildContext context,
    DatabaseController db,
    TablePage? page,
  ) {
    final safePage = page;
    if (safePage == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.first_page),
            onPressed: safePage.currentPage > 1 ? () => db.goToPage(1) : null,
            tooltip: '首页',
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed:
                safePage.currentPage > 1 ? () => db.prevPage() : null,
            tooltip: '上一页',
          ),
          const SizedBox(width: 8),
          Text('${safePage.currentPage} / ${safePage.totalPages}'),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: safePage.hasMore ? () => db.nextPage() : null,
            tooltip: '下一页',
          ),
          IconButton(
            icon: const Icon(Icons.last_page),
            onPressed:
                safePage.hasMore ? () => db.goToPage(safePage.totalPages) : null,
            tooltip: '末页',
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _handleRefresh(db),
            tooltip: '刷新',
          ),
        ],
      ),
    );
  }

  Future<void> _handleRefresh(DatabaseController db) async {
    final selectedPage = db.currentPage?.currentPage ?? 1;
    final horizontalOffset = _horizontalController.hasClients
        ? _horizontalController.offset
        : 0.0;
    final verticalOffset = _verticalController.hasClients
        ? _verticalController.offset
        : 0.0;

    final refreshAction = widget.onRefresh;
    if (refreshAction != null) {
      await refreshAction();
    } else {
      db.refresh();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_horizontalController.hasClients) {
        _horizontalController.jumpTo(horizontalOffset.clamp(
          0.0,
          _horizontalController.position.maxScrollExtent,
        ));
      }
      if (_verticalController.hasClients) {
        _verticalController.jumpTo(verticalOffset.clamp(
          0.0,
          _verticalController.position.maxScrollExtent,
        ));
      }
    });

    if (db.currentPage != null && db.currentPage!.currentPage != selectedPage) {
      db.goToPage(selectedPage);
    }
  }
}