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
    final parts = raw.split('_').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    if (parts.length == 1) return Locale(parts[0]);
    // BCP-47 disambiguation: 4-char Title-cased segments are script
    // subtags (Hans, Hant, Latn); everything else is a region code (TW,
    // US, 419). Avoids the trap of feeding `countryCode: ''` to
    // Locale.fromSubtags, which would store '' as the literal country
    // and break supportedLocales matching.
    final languageCode = parts[0];
    String? scriptCode;
    String? countryCode;
    for (final p in parts.skip(1)) {
      if (p.length == 4) {
        scriptCode = p;
      } else {
        countryCode = p;
      }
    }
    return Locale.fromSubtags(
      languageCode: languageCode,
      scriptCode: scriptCode,
      countryCode: countryCode,
    );
  }

  static String _encode(Locale l) {
    // Join only non-null subtags so a script-only locale (eg. zh_Hans
    // with no region) doesn't serialize to "zh_Hans_" with a trailing
    // underscore that round-trips into an invalid Locale.
    final parts = <String>[
      l.languageCode,
      if (l.scriptCode != null) l.scriptCode!,
      if (l.countryCode != null) l.countryCode!,
    ];
    return parts.join('_');
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
