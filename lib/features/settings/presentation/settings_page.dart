import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../state/app_settings_controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.strings;
    final settings = ref.watch(appSettingsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card.outlined(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.language,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment<String>(
                        value: 'zh',
                        label: Text(s.chinese),
                      ),
                      ButtonSegment<String>(
                        value: 'en',
                        label: Text(s.english),
                      ),
                    ],
                    selected: {settings.languageCode},
                    onSelectionChanged: (selection) {
                      final value = selection.first;
                      ref
                          .read(appSettingsControllerProvider)
                          .setLanguageCode(value, ref);
                    },
                    showSelectedIcon: false,
                    multiSelectionEnabled: false,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}