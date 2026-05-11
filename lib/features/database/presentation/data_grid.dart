import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/database_models.dart';
import '../../../state/database_controller.dart';

class DataGrid extends ConsumerStatefulWidget {
  final Future<void> Function()? onRefresh;
  final ValueChanged<Map<String, dynamic>>? onOpenRowDetail;
  final ValueChanged<Map<String, dynamic>>? onEditRow;
  final ValueChanged<Map<String, dynamic>>? onDeleteRow;

  const DataGrid({
    super.key,
    this.onRefresh,
    this.onOpenRowDetail,
    this.onEditRow,
    this.onDeleteRow,
  });

  @override
  ConsumerState<DataGrid> createState() => _DataGridState();
}

class _DataGridState extends ConsumerState<DataGrid> {
  final _searchController = TextEditingController();
  final _verticalController = ScrollController();
  final _horizontalController = ScrollController();

  @override
  void dispose() {
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索 ${db.currentTable}...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: db.searchTerm != null
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => db.setSearch(null),
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
          const Expanded(child: Center(child: Text('无数据'))),
          _buildPaginationBar(context, db, page),
        ],
      );
    }

    final columns = page.columns;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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
          child: SingleChildScrollView(
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              controller: _verticalController,
              child: DataTable(
                columnSpacing: 24,
                horizontalMargin: 12,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 84,
                columns: [
                  DataColumn(
                    label: Text('#',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  for (final col in columns)
                    DataColumn(
                      label: Text(col.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  const DataColumn(label: Text('操作')),
                ],
                rows: [
                  for (final row in page.rows)
                    DataRow(
                      onLongPress: widget.onOpenRowDetail == null
                          ? null
                          : () => widget.onOpenRowDetail?.call(row),
                      cells: [
                        DataCell(Text('${row['rowid'] ?? ''}')),
                        for (final col in columns)
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 260),
                              child: Text(
                                '${row[col.name] ?? ''}',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 3,
                              ),
                            ),
                          ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.visibility_outlined, size: 18),
                                tooltip: '详情',
                                visualDensity: VisualDensity.compact,
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
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),

        _buildPaginationBar(context, db, page),
      ],
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