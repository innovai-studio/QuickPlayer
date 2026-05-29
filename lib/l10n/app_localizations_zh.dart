import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get commonCancel => '取消';

  @override
  String get commonClose => '關閉';

  @override
  String get commonRetry => '重試';

  @override
  String get commonDownload => '下載';

  @override
  String get commonOk => '確定';

  @override
  String get languageSectionTitle => '語言';

  @override
  String get languageRowLabel => 'App 語言';

  @override
  String get languageOptionSystem => '跟隨系統';

  @override
  String get languageOptionEnglish => 'English';

  @override
  String get languageOptionChineseTraditional => '繁體中文';

  @override
  String get stemModelDownloadTitle => '下載音軌分離模型';

  @override
  String get stemModelBenefitOnDevice => '完全在裝置上執行,音檔不會上傳';

  @override
  String get stemModelBenefitNoLengthCap => '無長度限制,單首歌可分離整曲';

  @override
  String get stemModelBenefitOnceOnly => '只需下載一次,離線可用';

  @override
  String stemModelVariantNotice(String segment) {
    return '依您的裝置記憶體配置:$segment 秒片段模型';
  }

  @override
  String get stemModelDownloadingTitle => '下載模型中';

  @override
  String get stemModelConnecting => '連線中…';

  @override
  String stemModelPhaseGraph(int index, int count) {
    return '模型結構 ($index/$count)';
  }

  @override
  String stemModelPhaseWeights(int index, int count) {
    return '模型權重 ($index/$count)';
  }

  @override
  String get stemModelDownloadFailed => '下載失敗';

  @override
  String get stemSeparatingTitle => '分離音軌中';

  @override
  String get stemPhaseDecoding => '正在解碼音訊…';

  @override
  String get stemPhaseSeparating => '分離中(模型推論)…';

  @override
  String stemPhaseEncoding(int index, int count) {
    return '編碼中 ($index/$count)…';
  }

  @override
  String get stemPhaseDone => '完成';

  @override
  String get stemEtaEstimating => '預估中…';

  @override
  String stemFailedWithReason(String reason) {
    return '失敗:$reason';
  }

  @override
  String get stemNameDrums => '鼓組';

  @override
  String get stemNameBass => '貝斯';

  @override
  String get stemNameOther => '其他';

  @override
  String get stemNameVocals => '人聲';

  @override
  String etaSecondsRemaining(int seconds) {
    return '約 $seconds 秒';
  }

  @override
  String etaMinutesSecondsRemaining(int minutes, int seconds) {
    return '約 $minutes 分 $seconds 秒';
  }

  @override
  String etaMinutesRemaining(int minutes) {
    return '約 $minutes 分鐘';
  }

  @override
  String bytesProgress(String done, String total) {
    return '$done / $total MB';
  }
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw(): super('zh_TW');

  @override
  String get commonCancel => '取消';

  @override
  String get commonClose => '關閉';

  @override
  String get commonRetry => '重試';

  @override
  String get commonDownload => '下載';

  @override
  String get commonOk => '確定';

  @override
  String get languageSectionTitle => '語言';

  @override
  String get languageRowLabel => 'App 語言';

  @override
  String get languageOptionSystem => '跟隨系統';

  @override
  String get languageOptionEnglish => 'English';

  @override
  String get languageOptionChineseTraditional => '繁體中文';

  @override
  String get stemModelDownloadTitle => '下載音軌分離模型';

  @override
  String get stemModelBenefitOnDevice => '完全在裝置上執行,音檔不會上傳';

  @override
  String get stemModelBenefitNoLengthCap => '無長度限制,單首歌可分離整曲';

  @override
  String get stemModelBenefitOnceOnly => '只需下載一次,離線可用';

  @override
  String stemModelVariantNotice(String segment) {
    return '依您的裝置記憶體配置:$segment 秒片段模型';
  }

  @override
  String get stemModelDownloadingTitle => '下載模型中';

  @override
  String get stemModelConnecting => '連線中…';

  @override
  String stemModelPhaseGraph(int index, int count) {
    return '模型結構 ($index/$count)';
  }

  @override
  String stemModelPhaseWeights(int index, int count) {
    return '模型權重 ($index/$count)';
  }

  @override
  String get stemModelDownloadFailed => '下載失敗';

  @override
  String get stemSeparatingTitle => '分離音軌中';

  @override
  String get stemPhaseDecoding => '正在解碼音訊…';

  @override
  String get stemPhaseSeparating => '分離中(模型推論)…';

  @override
  String stemPhaseEncoding(int index, int count) {
    return '編碼中 ($index/$count)…';
  }

  @override
  String get stemPhaseDone => '完成';

  @override
  String get stemEtaEstimating => '預估中…';

  @override
  String stemFailedWithReason(String reason) {
    return '失敗:$reason';
  }

  @override
  String get stemNameDrums => '鼓組';

  @override
  String get stemNameBass => '貝斯';

  @override
  String get stemNameOther => '其他';

  @override
  String get stemNameVocals => '人聲';

  @override
  String etaSecondsRemaining(int seconds) {
    return '約 $seconds 秒';
  }

  @override
  String etaMinutesSecondsRemaining(int minutes, int seconds) {
    return '約 $minutes 分 $seconds 秒';
  }

  @override
  String etaMinutesRemaining(int minutes) {
    return '約 $minutes 分鐘';
  }

  @override
  String bytesProgress(String done, String total) {
    return '$done / $total MB';
  }
}
