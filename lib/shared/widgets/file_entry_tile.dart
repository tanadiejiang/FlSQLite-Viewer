import 'package:flutter/material.dart';

import '../../models/database_models.dart';

class FileEntryTile extends StatelessWidget {
  final DirectoryEntry entry;
  final VoidCallback? onTap;
  final bool showIcon;

  const FileEntryTile({
    super.key,
    required this.entry,
    this.onTap,
    this.showIcon = true,
  });

  bool get isDatabase {
    final lower = entry.name.toLowerCase();
    return lower.endsWith('.db') ||
        lower.endsWith('.sqlite') ||
        lower.endsWith('.sqlite3');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      leading: showIcon
          ? Icon(
              entry.isDirectory ? Icons.folder : Icons.insert_drive_file,
              color: entry.isDirectory
                  ? colorScheme.primary
                  : isDatabase
                      ? colorScheme.tertiary
                      : colorScheme.onSurfaceVariant,
            )
          : null,
      title: Text(
        entry.name,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: isDatabase ? FontWeight.w600 : null,
        ),
      ),
      subtitle: entry.isDirectory ? null : Text(entry.fullPath,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: colorScheme.onSurfaceVariant),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: entry.isDirectory
          ? const Icon(Icons.chevron_right, size: 20)
          : isDatabase
              ? Text('DB',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.tertiary,
                    fontWeight: FontWeight.bold,
                  ))
              : null,
      onTap: onTap,
      dense: true,
    );
  }
}