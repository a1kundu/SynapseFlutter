import 'package:flutter/material.dart';

/// Centralized app color constants.
///
/// All semantic colors used across the app are defined here,
/// eliminating hardcoded Color() values in widget files.
class AppColors {
  AppColors._();

  /// Seed color used when dynamic color is not available.
  static const Color seedColor = Colors.deepPurple;

  // ---------------------------------------------------------------------------
  // Green tonal palette – used for "available" / "vacant" status
  // ---------------------------------------------------------------------------

  static const Color greenContainerDark = Color(0xFF1B3A2A);
  static const Color greenContainerLight = Color(0xFFD4F5DC);

  static const Color greenBorderDark = Color(0xFF2E7D50);
  static const Color greenBorderLight = Color(0xFF43A047);

  static const Color greenButtonBgDark = Color(0xFF2D5E44);
  static const Color greenButtonBgLight = Color(0xFF8FCF9E);

  static const Color greenButtonFgDark = Color(0xFFD4F5DC);
  static const Color greenButtonFgLight = Color(0xFF0D4A22);

  static const Color greenTextDark = Color(0xFFA8DAB5);
  static const Color greenTextLight = Color(0xFF1B6B35);

  // ---------------------------------------------------------------------------
  // QR code
  // ---------------------------------------------------------------------------

  static const Color qrCodeColor = Color(0xFF1a237e);

  // ---------------------------------------------------------------------------
  // Member avatar palette
  // ---------------------------------------------------------------------------

  static const List<Color> avatarColors = [
    Colors.blue,
    Colors.teal,
    Colors.purple,
    Colors.green,
    Colors.orange,
    Colors.cyan,
    Colors.pink,
    Colors.red,
  ];

  // ---------------------------------------------------------------------------
  // Convenience helpers (resolve light/dark at call site)
  // ---------------------------------------------------------------------------

  static Color greenContainer(bool isDark) =>
      isDark ? greenContainerDark : greenContainerLight;

  static Color greenBorder(bool isDark) =>
      isDark ? greenBorderDark : greenBorderLight;

  static Color greenButtonBg(bool isDark) =>
      isDark ? greenButtonBgDark : greenButtonBgLight;

  static Color greenButtonFg(bool isDark) =>
      isDark ? greenButtonFgDark : greenButtonFgLight;

  static Color greenText(bool isDark) =>
      isDark ? greenTextDark : greenTextLight;
}
