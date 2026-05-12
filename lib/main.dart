import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
  }

  runApp(ProviderScope(child: FlSqliteViewerApp(initialOpenPaths: args)));

  if (Platform.isWindows) {
    const windowOptions = WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(900, 560),
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      await windowManager.show();
      await windowManager.focus();
    });
  }
}
