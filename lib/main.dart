import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'core/constants/app_colors.dart';
import 'core/storage/storage_service.dart';
import 'routing/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bridges just_audio playback to Android's MediaSession + foreground
  // service. Must run before any AudioPlayer is constructed -- once
  // initialised, every AudioPlayer with a MediaItem-tagged source
  // automatically gets lockscreen / notification / BT-headset controls
  // and survives backgrounding without Android killing it.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.quickplayer.quickplayer.channel.audio',
    androidNotificationChannelName: 'Music playback',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );

  // Set system UI style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize storage
  await StorageService().init();

  runApp(
    const ProviderScope(
      child: QuickPlayerApp(),
    ),
  );
}

class QuickPlayerApp extends StatelessWidget {
  const QuickPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'QuickPlayer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.dark(
          primary: AppColors.primaryStart,
          secondary: AppColors.accent,
          surface: AppColors.surfaceDark,
          error: AppColors.error,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: AppColors.primaryStart,
          inactiveTrackColor: AppColors.surfaceDark,
          thumbColor: AppColors.primaryStart,
          overlayColor: AppColors.primaryStart.withValues(alpha: 0.2),
        ),
      ),
      routerConfig: appRouter,
    );
  }
}
