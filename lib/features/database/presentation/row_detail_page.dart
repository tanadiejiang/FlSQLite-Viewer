import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/database_models.dart';

class RowDetailPage extends StatefulWidget {
  final DatabaseTable table;
  final Map<String, dynamic> row;
  final ValueChanged<Map<String, dynamic>>? onSave;

  const RowDetailPage({
    super.key,
    required this.table,
    required this.row,
    this.onSave,
  });

  @override
  State<RowDetailPage> createState() => _RowDetailPageState();
}

class _RowDetailPageState extends State<RowDetailPage> {
  final _controllers = <String, TextEditingController>{};
  final _nullFlags = <String, bool>{};
  late Map<String, dynamic> _currentRow;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _currentRow = Map<String, dynamic>.from(widget.row);
    _syncControllersFromRow();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑行' : '行详情'),
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.visibility_outlined : Icons.edit_outlined),
            tooltip: _isEditing ? '查看详情' : '编辑',
            onPressed: () {
              setState(() {
                _isEditing = !_isEditing;
                if (!_isEditing) {
                  _syncControllersFromRow();
                }
              });
            },
          ),
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: '保存',
              onPressed: _save,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final col in widget.table.columns)
            Card.outlined(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: _isEditing
                    ? _buildEditorField(context, theme, col)
                    : _buildReadonlyField(context, theme, col),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReadonlyField(
      BuildContext context, ThemeData theme, TableColumnInfo col) {
    final value = _currentRow[col.name];
    final display = value == null ? 'NULL' : value.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                col.name,
                style: theme.textTheme.titleMedium,
              ),
            ),
            Text(
              col.type.isEmpty ? 'any' : col.type,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SelectionArea(
          child: SelectableText(
            display,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: value == null
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditorField(
      BuildContext context, ThemeData theme, TableColumnInfo col) {
    final controller = _controllers[col.name]!;
    final isNull = _nullFlags[col.name] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${col.name} (${col.type.isEmpty ? 'any' : col.type})',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (col.notNull)
              Text(
                '必填',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            if (!col.notNull) ...[
              const SizedBox(width: 12),
              const Text('NULL', style: TextStyle(fontSize: 11)),
              Switch(
                value: isNull,
                onChanged: (value) {
                  setState(() {
                    _nullFlags[col.name] = value;
                    if (value) {
                      controller.clear();
                    }
                  });
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          enabled: !isNull,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          minLines: 1,
          maxLines: null,
          inputFormatters: [LengthLimitingTextInputFormatter(200000)],
          decoration: InputDecoration(
            hintText: isNull ? '(NULL)' : (col.defaultValue ?? ''),
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }

  void _syncControllersFromRow() {
    for (final col in widget.table.columns) {
      final value = _currentRow[col.name];
      _controllers.putIfAbsent(col.name, () => TextEditingController());
      _controllers[col.name]!.text = value?.toString() ?? '';
      _nullFlags[col.name] = value == null;
    }
  }

  void _save() {
    final values = <String, dynamic>{};
    for (final col in widget.table.columns) {
      if (_nullFlags[col.name] == true) {
        values[col.name] = null;
        continue;
      }
      final text = _controllers[col.name]!.text.trim();
      if (text.isEmpty && col.notNull) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${col.name} 不能为空')));
        return;
      }
      values[col.name] = text.isEmpty ? null : text;
    }

    widget.onSave?.call(values);
    setState(() {
      _currentRow = {..._currentRow, ...values};
      _isEditing = false;
      _syncControllersFromRow();
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存修改')));
  }
}