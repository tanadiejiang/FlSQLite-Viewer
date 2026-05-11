import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/database_models.dart';

class RowEditorDialog extends StatefulWidget {
  final DatabaseTable table;
  final Map<String, dynamic>? existingRow;
  final bool isEdit;

  const RowEditorDialog({
    super.key,
    required this.table,
    this.existingRow,
    this.isEdit = false,
  });

  @override
  State<RowEditorDialog> createState() => _RowEditorDialogState();
}

class _RowEditorDialogState extends State<RowEditorDialog> {
  final _controllers = <String, TextEditingController>{};
  final _nullFlags = <String, bool>{};

  @override
  void initState() {
    super.initState();
    for (final col in widget.table.columns) {
      _controllers[col.name] = TextEditingController(
        text: widget.existingRow?[col.name]?.toString() ?? '',
      );
      _nullFlags[col.name] = widget.existingRow?[col.name] == null;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width > 600;

    return AlertDialog(
      title: Text(widget.isEdit ? '编辑行' : '新增行'),
      content: SizedBox(
        width: isWide ? 560 : double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final col in widget.table.columns)
                if (!col.primaryKey || widget.isEdit)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${col.name} (${col.type.isEmpty ? 'any' : col.type})',
                                style: theme.textTheme.labelMedium,
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
                                value: _nullFlags[col.name] ?? false,
                                onChanged: (v) {
                                  setState(() {
                                    _nullFlags[col.name] = v;
                                    if (v) {
                                      _controllers[col.name]!.clear();
                                    }
                                  });
                                },
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _controllers[col.name],
                          enabled: !(_nullFlags[col.name] ?? false),
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          minLines: 1,
                          maxLines: null,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(200000),
                          ],
                          decoration: InputDecoration(
                            hintText: _nullFlags[col.name] == true
                                ? '(NULL)'
                                : (col.defaultValue ?? ''),
                            alignLabelWithHint: true,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.isEdit ? '保存' : '新增'),
        ),
      ],
    );
  }

  void _submit() {
    final values = <String, dynamic>{};
    for (final col in widget.table.columns) {
      if (col.primaryKey && widget.isEdit) {
        continue;
      }
      if (col.primaryKey && !widget.isEdit) {
        continue;
      }
      if (_nullFlags[col.name] == true) {
        values[col.name] = null;
      } else {
        final text = _controllers[col.name]!.text.trim();
        if (text.isEmpty && col.notNull) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('${col.name} 不能为空')));
          return;
        }
        values[col.name] = text.isEmpty ? null : text;
      }
    }
    Navigator.of(context).pop(values);
  }
}