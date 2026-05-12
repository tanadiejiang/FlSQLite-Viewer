import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../state/file_browser_controller.dart';
import '../../../state/file_access_controller.dart';
import '../../../models/database_models.dart';
import '../../../shared/widgets/file_entry_tile.dart';
import '../../../shared/widgets/path_breadcrumbs.dart';

class FileBrowserPage extends ConsumerStatefulWidget {
  final Future<void> Function(String dbPath, FileAccessMode? forcedMode)?
      onDatabaseSelected;

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
      final initialPath = await browser.defaultInitialPath();
      if (!mounted) return;
      await browser.navigateTo(initialPath);
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
    final access = ref.read(fileAccessControllerProvider);
    final s = context.strings;
    if (_filterController.text != browser.filter) {
      _filterController.value = TextEditingValue(
        text: browser.filter,
        selection: TextSelection.collapsed(offset: browser.filter.length),
      );
    }
    final theme = Theme.of(context);
    final isWide = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.fileBrowserTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _filterController,
              decoration: InputDecoration(
                hintText: s.filterFilesHint,
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
              pathForIndex: browser.pathForSegmentIndex,
              compact: !isWide,
            ),
          ),
          if (browser.isDesktop)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final drive in browser.desktopShortcutEntries) ...[
                        ActionChip(
                          avatar: const Icon(Icons.drive_file_move, size: 16),
                          label: Text(
                            drive.name,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onPressed: () => browser.navigateTo(drive.fullPath),
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final tp in FileBrowserController.testPaths) ...[
                      ActionChip(
                        avatar: const Icon(Icons.bolt, size: 16),
                        label: Text(
                          tp['label']!,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: () {
                          final path = tp['path']!;
                          final parent =
                              path.substring(0, path.lastIndexOf('/'));
                          final modeName = tp['mode'];
                          final forcedMode = modeName != null
                              ? fileAccessModeFromName(modeName)
                              : null;
                          final strictMode = forcedMode;
                          if (strictMode == FileAccessMode.root &&
                              !access.canUseMode(strictMode!)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(access
                                    .accessModeUnavailableMessage(strictMode)),
                              ),
                            );
                            return;
                          }
                          browser.navigateTo(
                            parent,
                            forcedMode: forcedMode,
                          );
                        },
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                selected: browser.showDatabasesOnly,
                onSelected: browser.setShowDatabasesOnly,
                label: Text(s.showDatabasesOnly),
                avatar: const Icon(Icons.storage, size: 16),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Up button
          if (browser.currentPath != '/')
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: Text(s.goUp),
              dense: true,
              onTap: () => browser.goUp(),
            ),
          // Content
          Expanded(
            child: browser.isLoading
                ? const Center(child: CircularProgressIndicator())
                : browser.errorMessage != null
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: Card.outlined(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Center(
                                      child: Icon(Icons.error_outline,
                                          size: 48, color: Colors.red),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      browser.errorSummary ?? s.directoryLoadFailed,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    if (browser.errorDetails != null &&
                                        browser.errorDetails !=
                                            browser.errorSummary) ...[
                                      const SizedBox(height: 8),
                                      ExpansionTile(
                                        tilePadding: EdgeInsets.zero,
                                        childrenPadding: EdgeInsets.zero,
                                        title: Text(s.viewDetails),
                                        children: [
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: theme.colorScheme
                                                  .surfaceContainerLow,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: SelectableText(
                                              browser.errorDetails!,
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.center,
                                      child: ElevatedButton(
                                        onPressed: () => browser.retry(),
                                        child: Text(s.retry),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : browser.entries.isEmpty
                        ? Center(
                            child: Text(
                              browser.filter.isNotEmpty
                                  ? s.noFilterMatches
                                  : browser.showDatabasesOnly
                                      ? s.noDatabaseFiles
                                      : s.directoryEmpty,
                            ),
                          )
                        : ListView.builder(
                            itemCount: browser.entries.length,
                            itemBuilder: (context, index) {
                              final entry = browser.entries[index];
                              return FileEntryTile(
                                entry: entry,
                                onTap: () {
                                  if (entry.isDirectory) {
                                    browser.navigateTo(entry.fullPath);
                                  } else if (browser
                                      .isDatabaseFile(entry.name)) {
                                    widget.onDatabaseSelected?.call(
                                      entry.fullPath,
                                      browser.lastForcedMode,
                                    );
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