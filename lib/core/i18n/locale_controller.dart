import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/storage_service.dart';

/// Source of truth for the app's UI locale.
///
/// `null` means "follow the OS" — `MaterialApp` then falls back to its
/// `localeResolutionCallback`, which picks the closest match from
/// `AppLocalizations.supportedLocales` (eg. a zh-Hant-TW system gets
/// `zh_TW`, a zh-Hans-CN system gets the `zh` base which we ship as the
/// same Traditional Chinese content until a Simplified variant lands).
///
/// A non-null value is a hard override the user picked in Settings; we
/// persist it via [StorageService] so the choice survives relaunches.
class LocaleController extends StateNotifier<Locale?> {
  LocaleController() : super(_load());

  static const _storageKey = 'localeOverride';

  static Locale? _load() {
    // Stored as the canonical `languageCode[_scriptCode][_countryCode]`
    // form. Anything we can't parse falls back to system.
    final raw = StorageService().getSetting<String>(_storageKey);
    return _parse(raw);
  }

  static Locale? _parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('_');
    return switch (parts.length) {
      1 => Locale(parts[0]),
      2 => Locale(parts[0], parts[1]),
      _ => Locale.fromSubtags(
          languageCode: parts[0],
          scriptCode: parts[1],
          countryCode: parts[2],
        ),
    };
  }

  static String _encode(Locale l) {
    if (l.scriptCode == null && l.countryCode == null) {
      return l.languageCode;
    }
    if (l.scriptCode == null) {
      return '${l.languageCode}_${l.countryCode}';
    }
    return '${l.languageCode}_${l.scriptCode}_${l.countryCode ?? ''}';
  }

  /// Pass `null` to revert to "follow OS".
  Future<void> setLocale(Locale? locale) async {
    state = locale;
    final storage = StorageService();
    if (locale == null) {
      // `delete` would be cleaner but the box only exposes get/set; an
      // empty string round-trips through `_parse` as null, same effect.
      await storage.setSetting(_storageKey, '');
    } else {
      await storage.setSetting(_storageKey, _encode(locale));
    }
  }
}

final localeControllerProvider =
    StateNotifierProvider<LocaleController, Locale?>(
        (ref) => LocaleController());
