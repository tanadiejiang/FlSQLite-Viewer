import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import 'file_access_controller.dart';

class AppSettingsController extends ChangeNotifier {
  static const _languagePrefKey = 'app_language_code';

  String _languageCode = 'zh';
  bool _loaded = false;

  String get languageCode => _languageCode;
  Locale get locale => Locale(_languageCode);
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _languageCode = prefs.getString(_languagePrefKey) ?? 'zh';
    AppStrings.updateCurrentLanguageCode(_languageCode);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setLanguageCode(String languageCode, WidgetRef ref) async {
    if (_languageCode == languageCode) {
      return;
    }
    _languageCode = languageCode;
    AppStrings.updateCurrentLanguageCode(languageCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languagePrefKey, languageCode);
    await ref.read(fileAccessControllerProvider).refreshLocalization();
    notifyListeners();
  }
}

final appSettingsControllerProvider =
    ChangeNotifierProvider<AppSettingsController>((ref) {
  return AppSettingsController();
});