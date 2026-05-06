import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'core/constants/app_colors.dart';
import 'core/storage/storage_service.dart';
import 'routing/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // JustAudioMediaKit is only the fallback for Linux/Windows desktop -- on
  // Android/iOS the regular just_audio platform plugin is used. Calling
  // ensureInitialized() unconditionally spins up libmpv as a parallel
  // audio system that survives Flutter VM teardown, which causes audio
  // to keep playing after the app is closed. Gate on platform so mobile
  // builds don't initialise it.
  if (Platform.isLinux || Platform.isWindows) {
    JustAudioMediaKit.ensureInitialized();
  }

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
