import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_strings.dart';
import '../../../models/database_models.dart';

class RowDetailPage extends StatefulWidget {
  final DatabaseTable table;
  final Map<String, dynamic> row;
  final ValueChanged<Map<String, dynamic>>? onSave;
  final ValueChanged<Map<String, dynamic>>? onDelete;

  const RowDetailPage({
    super.key,
    required this.table,
    required this.row,
    this.onSave,
    this.onDelete,
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
    final s = context.strings;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? s.editRow : s.rowDetails),
        actions: _buildAppBarActions(s),
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
                    ? _buildEditorField(context, theme, s, col)
                    : _buildReadonlyField(context, theme, s, col),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildAppBarActions(AppStrings s) {
    final deleteButton = IconButton(
      icon: Icon(
        Icons.delete_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      tooltip: s.delete,
      onPressed: widget.onDelete == null ? null : _delete,
    );
    final toggleButton = IconButton(
      icon: Icon(
        _isEditing ? Icons.visibility_outlined : Icons.edit_outlined,
        color: _isEditing ? null : Colors.orange,
      ),
      tooltip: _isEditing ? s.viewDetailsAction : s.edit,
      onPressed: () {
        setState(() {
          _isEditing = !_isEditing;
          if (!_isEditing) {
            _syncControllersFromRow();
          }
        });
      },
    );

    if (_isEditing) {
      return [
        deleteButton,
        const SizedBox(width: 48),
        toggleButton,
        IconButton(
          icon: const Icon(
            Icons.save_outlined,
            color: Color.fromARGB(255, 93, 169, 231),
          ),
          tooltip: s.save,
          onPressed: _save,
        ),
      ];
    }

    return [deleteButton, const SizedBox(width: 96), toggleButton];
  }

  Future<void> _delete() async {
    final s = context.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.confirmDelete),
        content: Text(s.confirmDeleteRowContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.delete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    widget.onDelete?.call(_currentRow);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.rowDeletedPendingSave)),
    );
    Navigator.of(context).pop();
  }

  Widget _buildReadonlyField(
    BuildContext context,
    ThemeData theme,
    AppStrings s,
    TableColumnInfo col,
  ) {
    final value = _currentRow[col.name];
    final display = value == null ? s.nullLabel : value.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(col.name, style: theme.textTheme.titleMedium)),
            Text(
              col.type.isEmpty ? s.anyType : col.type,
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
    BuildContext context,
    ThemeData theme,
    AppStrings s,
    TableColumnInfo col,
  ) {
    final controller = _controllers[col.name]!;
    final isNull = _nullFlags[col.name] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${col.name} (${col.type.isEmpty ? s.anyType : col.type})',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (col.notNull)
              Text(
                s.requiredField,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            if (!col.notNull) ...[
              const SizedBox(width: 12),
              Text(s.nullLabel, style: const TextStyle(fontSize: 11)),
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
            hintText: isNull ? '(${s.nullLabel})' : (col.defaultValue ?? ''),
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
    final s = context.strings;
    final values = <String, dynamic>{};
    for (final col in widget.table.columns) {
      if (_nullFlags[col.name] == true) {
        values[col.name] = null;
        continue;
      }
      final text = _controllers[col.name]!.text.trim();
      if (text.isEmpty && col.notNull) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.fieldCannotBeEmpty(col.name))),
        );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.changesSaved)),
    );
  }
}