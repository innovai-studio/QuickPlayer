class AppConstants {
  AppConstants._();

  // App info
  static const appName = 'QuickPlayer';
  static const appVersion = '1.3.0';

  // Audio settings
  static const double minSpeed = 0.25;
  static const double maxSpeed = 2.0;
  static const double defaultSpeed = 1.0;
  static const double speedStep = 0.05;

  static const int minPitchSemitones = -12;
  static const int maxPitchSemitones = 12;
  static const int defaultPitchSemitones = 0;

  // Preset speeds
  static const List<double> presetSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5];

  // Hive box names
  static const String tracksBox = 'tracks';
  static const String markersBox = 'markers';
  static const String settingsBox = 'settings';
  static const String playlistsBox = 'playlists';

  // Supported audio formats
  static const List<String> supportedFormats = [
    'mp3',
    'wav',
    'm4a',
    'aac',
    'flac',
    'ogg',
  ];
}
