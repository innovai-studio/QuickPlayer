import 'package:hive/hive.dart';

part 'app_settings.g.dart';

@HiveType(typeId: 2)
class AppSettings extends HiveObject {
  @HiveField(0)
  double defaultSpeed;

  @HiveField(1)
  int defaultPitchSemitones;

  @HiveField(2)
  bool showWaveform;

  @HiveField(3)
  bool keepScreenOn;

  AppSettings({
    this.defaultSpeed = 1.0,
    this.defaultPitchSemitones = 0,
    this.showWaveform = true,
    this.keepScreenOn = true,
  });

  AppSettings copyWith({
    double? defaultSpeed,
    int? defaultPitchSemitones,
    bool? showWaveform,
    bool? keepScreenOn,
  }) {
    return AppSettings(
      defaultSpeed: defaultSpeed ?? this.defaultSpeed,
      defaultPitchSemitones: defaultPitchSemitones ?? this.defaultPitchSemitones,
      showWaveform: showWaveform ?? this.showWaveform,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    );
  }
}
