import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Background
  static const background = Color(0xFF0A0A0B);
  static const surfaceDark = Color(0xFF1C1C1E);

  // Primary (Gradient)
  static const primaryStart = Color(0xFF667EEA);
  static const primaryEnd = Color(0xFF764BA2);

  // Accent colors
  static const accent = Color(0xFF00D9FF); // A-B markers
  static const success = Color(0xFF34C759); // Playing
  static const warning = Color(0xFFFF9500);
  static const error = Color(0xFFFF3B30);

  // Text
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0x99FFFFFF); // 60%

  // Border & Divider
  static const border = Color(0x1FFFFFFF); // 12%
  static const divider = Color(0x33FFFFFF); // 20%

  // Card
  static const cardBackground = Color(0xB81C1C1E); // 72%

  // Gradient
  static const primaryGradient = LinearGradient(
    colors: [primaryStart, primaryEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
