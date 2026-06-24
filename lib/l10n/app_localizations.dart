import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale('zh', 'TW')
  ];

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get commonDownload;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @languageSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSectionTitle;

  /// No description provided for @languageRowLabel.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get languageRowLabel;

  /// No description provided for @languageOptionSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageOptionSystem;

  /// No description provided for @languageOptionEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageOptionEnglish;

  /// No description provided for @languageOptionChineseTraditional.
  ///
  /// In en, this message translates to:
  /// **'繁體中文'**
  String get languageOptionChineseTraditional;

  /// No description provided for @stemModelDownloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Download stem-separation model'**
  String get stemModelDownloadTitle;

  /// No description provided for @stemModelBenefitOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Runs 100% on-device — no upload'**
  String get stemModelBenefitOnDevice;

  /// No description provided for @stemModelBenefitNoLengthCap.
  ///
  /// In en, this message translates to:
  /// **'No length cap — separate full songs'**
  String get stemModelBenefitNoLengthCap;

  /// No description provided for @stemModelBenefitOnceOnly.
  ///
  /// In en, this message translates to:
  /// **'One-time download, then offline'**
  String get stemModelBenefitOnceOnly;

  /// No description provided for @stemModelVariantNotice.
  ///
  /// In en, this message translates to:
  /// **'Picked for your device RAM: {segment}s-segment model'**
  String stemModelVariantNotice(String segment);

  /// No description provided for @stemModelDownloadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Downloading model'**
  String get stemModelDownloadingTitle;

  /// No description provided for @stemModelConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get stemModelConnecting;

  /// No description provided for @stemModelPhaseGraph.
  ///
  /// In en, this message translates to:
  /// **'Graph ({index}/{count})'**
  String stemModelPhaseGraph(int index, int count);

  /// No description provided for @stemModelPhaseWeights.
  ///
  /// In en, this message translates to:
  /// **'Weights ({index}/{count})'**
  String stemModelPhaseWeights(int index, int count);

  /// No description provided for @stemModelDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get stemModelDownloadFailed;

  /// No description provided for @stemSeparatingTitle.
  ///
  /// In en, this message translates to:
  /// **'Separating stems'**
  String get stemSeparatingTitle;

  /// No description provided for @stemPhaseDecoding.
  ///
  /// In en, this message translates to:
  /// **'Decoding audio…'**
  String get stemPhaseDecoding;

  /// No description provided for @stemPhaseSeparating.
  ///
  /// In en, this message translates to:
  /// **'Separating (model inference)…'**
  String get stemPhaseSeparating;

  /// No description provided for @stemPhaseEncoding.
  ///
  /// In en, this message translates to:
  /// **'Encoding ({index}/{count})…'**
  String stemPhaseEncoding(int index, int count);

  /// No description provided for @stemPhaseDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get stemPhaseDone;

  /// No description provided for @stemEtaEstimating.
  ///
  /// In en, this message translates to:
  /// **'Estimating…'**
  String get stemEtaEstimating;

  /// No description provided for @stemFailedWithReason.
  ///
  /// In en, this message translates to:
  /// **'Failed: {reason}'**
  String stemFailedWithReason(String reason);

  /// No description provided for @stemNameDrums.
  ///
  /// In en, this message translates to:
  /// **'Drums'**
  String get stemNameDrums;

  /// No description provided for @stemNameBass.
  ///
  /// In en, this message translates to:
  /// **'Bass'**
  String get stemNameBass;

  /// No description provided for @stemNameOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get stemNameOther;

  /// No description provided for @stemNameVocals.
  ///
  /// In en, this message translates to:
  /// **'Vocals'**
  String get stemNameVocals;

  /// No description provided for @etaSecondsRemaining.
  ///
  /// In en, this message translates to:
  /// **'~{seconds}s remaining'**
  String etaSecondsRemaining(int seconds);

  /// No description provided for @etaMinutesSecondsRemaining.
  ///
  /// In en, this message translates to:
  /// **'~{minutes}m {seconds}s remaining'**
  String etaMinutesSecondsRemaining(int minutes, int seconds);

  /// No description provided for @etaMinutesRemaining.
  ///
  /// In en, this message translates to:
  /// **'~{minutes} min remaining'**
  String etaMinutesRemaining(int minutes);

  /// No description provided for @bytesProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} / {total} MB'**
  String bytesProgress(String done, String total);
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {

  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh': {
  switch (locale.countryCode) {
    case 'TW': return AppLocalizationsZhTw();
   }
  break;
   }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'zh': return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
