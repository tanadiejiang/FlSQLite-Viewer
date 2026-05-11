import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Android 高级访问'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '启用高级访问模式后，您可以通过特殊的文件访问通道打开受保护或受限目录中的 SQLite 数据库文件。',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),

          // All files access
          AccessSwitchTile(
            capability: capabilities[FileAccessMode.manageAllFiles]!,
            onToggle: () {
              final nextEnabled =
                  !capabilities[FileAccessMode.manageAllFiles]!.enabled;
              controller.setCapabilityEnabled(
                  FileAccessMode.manageAllFiles, nextEnabled);
            },
            onAction: () => controller.openManageAllFilesSettings(),
          ),

          // Root
          AccessSwitchTile(
            capability: capabilities[FileAccessMode.root]!,
            onToggle: () {
              final nextEnabled = !capabilities[FileAccessMode.root]!.enabled;
              controller.setCapabilityEnabled(FileAccessMode.root, nextEnabled);
              if (nextEnabled) {
                controller.checkAllStatuses(forceRefresh: true);
              }
            },
            onAction: () => controller.checkAllStatuses(forceRefresh: true),
          ),

          // Shizuku
          AccessSwitchTile(
            capability: capabilities[FileAccessMode.shizuku]!,
            onToggle: () {
              final nextEnabled =
                  !capabilities[FileAccessMode.shizuku]!.enabled;
              controller.setCapabilityEnabled(FileAccessMode.shizuku, nextEnabled);
              if (nextEnabled) {
                controller.checkAllStatuses(forceRefresh: true);
              }
            },
            onAction: () => controller.openShizukuApp(),
          ),

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('安全提示',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Root 和 Shizuku 模式具有系统级权限。\n'
                  '仅在您完全了解风险的情况下启用。\n'
                  '修改应用私有数据可能导致该应用工作异常或数据丢失。',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
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
              label: const Text('刷新所有状态'),
            ),
          ),
        ],
      ),
    );
  }
}