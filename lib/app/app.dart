import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../state/app_settings_controller.dart';
import '../ui/home_page.dart';

class FlSqliteViewerApp extends ConsumerStatefulWidget {
  const FlSqliteViewerApp({super.key});

  @override
  ConsumerState<FlSqliteViewerApp> createState() => _FlSqliteViewerAppState();
}

class _FlSqliteViewerAppState extends ConsumerState<FlSqliteViewerApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(appSettingsControllerProvider).load());
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsControllerProvider);

    return MaterialApp(
      title: AppStrings.current.appName,
      debugShowCheckedModeBanner: false,
      locale: settings.locale,
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}