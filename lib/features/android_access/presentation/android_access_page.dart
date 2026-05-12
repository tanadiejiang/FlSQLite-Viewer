import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../models/database_models.dart';
import '../../../state/file_access_controller.dart';
import '../../../shared/widgets/access_switch_tile.dart';

class AndroidAccessPage extends ConsumerStatefulWidget {
  const AndroidAccessPage({super.key});

  @override
  ConsumerState<AndroidAccessPage> createState() => _AndroidAccessPageState();
}

class _AndroidAccessPageState extends ConsumerState<AndroidAccessPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() async {
      final controller = ref.read(fileAccessControllerProvider);
      await controller.loadPreferences();
      await controller.checkAllStatuses(forceRefresh: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Future.microtask(() async {
        if (!mounted) return;
        await ref
            .read(fileAccessControllerProvider)
            .checkAllStatuses(forceRefresh: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(fileAccessControllerProvider);
    final capabilities = controller.capabilities;
    final theme = Theme.of(context);
    final s = context.strings;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.androidAdvancedAccessTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              s.androidAdvancedAccessIntro,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
          AccessSwitchTile(
            capability: capabilities[FileAccessMode.manageAllFiles]!,
            onToggle: () {
              final nextEnabled =
                  !capabilities[FileAccessMode.manageAllFiles]!.enabled;
              controller.setCapabilityEnabled(
                FileAccessMode.manageAllFiles,
                nextEnabled,
              );
            },
            onAction: () => controller.openManageAllFilesSettings(),
          ),
          AccessSwitchTile(
            capability: capabilities[FileAccessMode.root]!,
            onToggle: () {
              final nextEnabled = !capabilities[FileAccessMode.root]!.enabled;
              controller.setCapabilityEnabled(FileAccessMode.root, nextEnabled);
            },
            onAction: () => controller.checkAllStatuses(forceRefresh: true),
          ),
          AccessSwitchTile(
            capability: capabilities[FileAccessMode.shizuku]!,
            onToggle: () {
              final nextEnabled =
                  !capabilities[FileAccessMode.shizuku]!.enabled;
              controller.setCapabilityEnabled(FileAccessMode.shizuku, nextEnabled);
            },
            onAction: () async {
              final granted = await controller.requestShizukuPermission();
              if (!context.mounted) return;
              await controller.checkAllStatuses(forceRefresh: true);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    granted ? s.shizukuAuthorized : s.shizukuUnauthorized,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.securityNotice,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  s.securityNoticeContent,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => controller.checkAllStatuses(forceRefresh: true),
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(s.refreshAllStatuses),
            ),
          ),
        ],
      ),
    );
  }
}