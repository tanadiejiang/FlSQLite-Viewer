import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/file_browser_controller.dart';
import '../../../state/file_access_controller.dart';
import '../../../models/database_models.dart';
import '../../../shared/widgets/file_entry_tile.dart';
import '../../../shared/widgets/path_breadcrumbs.dart';

class FileBrowserPage extends ConsumerStatefulWidget {
  final Function(String dbPath)? onDatabaseSelected;

  const FileBrowserPage({super.key, this.onDatabaseSelected});

  @override
  ConsumerState<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends ConsumerState<FileBrowserPage> {
  final _filterController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final access = ref.read(fileAccessControllerProvider);
      await access.ensureInitialized();
      if (!mounted) return;
      final browser = ref.read(fileBrowserControllerProvider);
      browser.navigateTo('/storage/emulated/0/');
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final browser = ref.watch(fileBrowserControllerProvider);
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('文件浏览器'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _filterController,
              decoration: InputDecoration(
                hintText: '过滤文件/目录...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _filterController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _filterController.clear();
                          browser.setFilter('');
                        },
                      )
                    : null,
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) => browser.setFilter(v),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Breadcrumbs
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: theme.colorScheme.surfaceContainerLow,
            child: PathBreadcrumbs(
              segments: browser.pathSegments,
              onSegmentTap: (path) => browser.navigateTo(path),
              compact: !isWide,
            ),
          ),
          // Test path shortcuts
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Wrap(
              spacing: 6,
              children: [
                for (final tp in FileBrowserController.testPaths)
                  ActionChip(
                    avatar: const Icon(Icons.bolt, size: 16),
                    label: Text(tp['label']!, style: const TextStyle(fontSize: 11)),
                    onPressed: () {
                      final path = tp['path']!;
                      final parent =
                          path.substring(0, path.lastIndexOf('/'));
                      final modeName = tp['mode'];
                      final forcedMode = modeName != null
                          ? fileAccessModeFromName(modeName)
                          : null;
                      browser.navigateTo(parent,
                          forcedMode: forcedMode);
                    },
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          // Up button
          if (browser.currentPath != '/')
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: const Text('上一级'),
              dense: true,
              onTap: () => browser.goUp(),
            ),
          // Content
          Expanded(
            child: browser.isLoading
                ? const Center(child: CircularProgressIndicator())
                : browser.errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                size: 48, color: Colors.red),
                            const SizedBox(height: 8),
                            Text(browser.errorMessage!),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: () => browser.retry(),
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : browser.entries.isEmpty
                        ? const Center(child: Text('目录为空'))
                        : ListView.builder(
                            itemCount: browser.entries.length,
                            itemBuilder: (context, index) {
                              final entry = browser.entries[index];
                              return FileEntryTile(
                                entry: entry,
                                onTap: () {
                                  if (entry.isDirectory) {
                                    browser
                                        .navigateTo(entry.fullPath);
                                  } else if (browser
                                      .isDatabaseFile(entry.name)) {
                                    widget.onDatabaseSelected
                                        ?.call(entry.fullPath);
                                  }
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}