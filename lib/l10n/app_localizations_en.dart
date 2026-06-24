import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonClose => 'Close';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonDownload => 'Download';

  @override
  String get commonOk => 'OK';

  @override
  String get languageSectionTitle => 'Language';

  @override
  String get languageRowLabel => 'App language';

  @override
  String get languageOptionSystem => 'System default';

  @override
  String get languageOptionEnglish => 'English';

  @override
  String get languageOptionChineseTraditional => '繁體中文';

  @override
  String get stemModelDownloadTitle => 'Download stem-separation model';

  @override
  String get stemModelBenefitOnDevice => 'Runs 100% on-device — no upload';

  @override
  String get stemModelBenefitNoLengthCap => 'No length cap — separate full songs';

  @override
  String get stemModelBenefitOnceOnly => 'One-time download, then offline';

  @override
  String stemModelVariantNotice(String segment) {
    return 'Picked for your device RAM: ${segment}s-segment model';
  }

  @override
  String get stemModelDownloadingTitle => 'Downloading model';

  @override
  String get stemModelConnecting => 'Connecting…';

  @override
  String stemModelPhaseGraph(int index, int count) {
    return 'Graph ($index/$count)';
  }

  @override
  String stemModelPhaseWeights(int index, int count) {
    return 'Weights ($index/$count)';
  }

  @override
  String get stemModelDownloadFailed => 'Download failed';

  @override
  String get stemSeparatingTitle => 'Separating stems';

  @override
  String get stemPhaseDecoding => 'Decoding audio…';

  @override
  String get stemPhaseSeparating => 'Separating (model inference)…';

  @override
  String stemPhaseEncoding(int index, int count) {
    return 'Encoding ($index/$count)…';
  }

  @override
  String get stemPhaseDone => 'Done';

  @override
  String get stemEtaEstimating => 'Estimating…';

  @override
  String stemFailedWithReason(String reason) {
    return 'Failed: $reason';
  }

  @override
  String get stemNameDrums => 'Drums';

  @override
  String get stemNameBass => 'Bass';

  @override
  String get stemNameOther => 'Other';

  @override
  String get stemNameVocals => 'Vocals';

  @override
  String etaSecondsRemaining(int seconds) {
    return '~${seconds}s remaining';
  }

  @override
  String etaMinutesSecondsRemaining(int minutes, int seconds) {
    return '~${minutes}m ${seconds}s remaining';
  }

  @override
  String etaMinutesRemaining(int minutes) {
    return '~$minutes min remaining';
  }

  @override
  String bytesProgress(String done, String total) {
    return '$done / $total MB';
  }
}
