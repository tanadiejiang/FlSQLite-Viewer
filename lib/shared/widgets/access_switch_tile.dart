import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../models/database_models.dart';

class AccessSwitchTile extends ConsumerWidget {
  final AccessCapability capability;
  final VoidCallback? onToggle;
  final VoidCallback? onAction;

  const AccessSwitchTile({
    super.key,
    required this.capability,
    this.onToggle,
    this.onAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = context.strings;
    final statusColorScheme = capability.available
        ? (background: colorScheme.primaryContainer, foreground: colorScheme.onPrimaryContainer)
        : (background: colorScheme.errorContainer, foreground: colorScheme.onErrorContainer);
    final usageHint = _usageHint(s);

    return Card.outlined(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconForMode(capability.mode),
                    color: colorScheme.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(capability.label,
                      style: theme.textTheme.titleSmall),
                ),
                if (capability.isChecking)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (capability.statusText != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColorScheme.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      capability.statusText!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColorScheme.foreground,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Switch(
                  value: capability.enabled,
                  onChanged: (_) => onToggle?.call(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              capability.description,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            if (usageHint != null) ...[
              const SizedBox(height: 4),
              Text(
                usageHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (onAction != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onAction,
                  child: Text(_actionLabelForMode(capability.mode, s)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? _usageHint(AppStrings s) {
    if (capability.isChecking) {
      return null;
    }
    if (capability.available && capability.enabled) {
      return s.enabledInAccessChain;
    }
    if (capability.available && !capability.enabled) {
      return s.authorizedButDisabled;
    }
    if (!capability.available && capability.enabled) {
      return s.enabledButUnavailable;
    }
    return s.currentlyDisabled;
  }

  IconData _iconForMode(FileAccessMode mode) {
    switch (mode) {
      case FileAccessMode.manageAllFiles:
        return Icons.folder_open;
      case FileAccessMode.root:
        return Icons.terminal;
      case FileAccessMode.shizuku:
        return Icons.hub;
      default:
        return Icons.folder;
    }
  }

  String _actionLabelForMode(FileAccessMode mode, AppStrings s) {
    switch (mode) {
      case FileAccessMode.manageAllFiles:
        return s.openSystemSettings;
      case FileAccessMode.root:
        return s.checkRootStatus;
      case FileAccessMode.shizuku:
        return s.requestShizukuPermission;
      default:
        return '';
    }
  }
}