import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Global theme notifiers
// ---------------------------------------------------------------------------

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);
final ValueNotifier<bool> dynamicColorNotifier = ValueNotifier(true);

Future<void> setThemeMode(ThemeMode mode) async {
  themeNotifier.value = mode;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('themeMode', mode.name);
}

Future<void> setDynamicColor(bool enabled) async {
  dynamicColorNotifier.value = enabled;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('dynamicColor', enabled);
}

/// Load persisted theme preferences. Call once from [main].
Future<void> loadThemePreferences() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('themeMode');
  if (saved != null) {
    themeNotifier.value = ThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ThemeMode.system,
    );
  }
  dynamicColorNotifier.value = prefs.getBool('dynamicColor') ?? true;
}

// ---------------------------------------------------------------------------
// Theme builder
// ---------------------------------------------------------------------------

/// Strips [fontFamily] from every [TextStyle] in [textTheme] so the
/// platform's default typeface is used instead of Material's bundled Roboto.
/// On Android this respects the user's system font preference (e.g. Samsung,
/// Xiaomi, etc. let users pick a custom system-wide font).
TextTheme _useSystemFont(TextTheme textTheme) {
  TextStyle? strip(TextStyle? s) {
    if (s == null) return null;
    return TextStyle(
      inherit: s.inherit,
      color: s.color,
      backgroundColor: s.backgroundColor,
      fontSize: s.fontSize,
      fontWeight: s.fontWeight,
      fontStyle: s.fontStyle,
      letterSpacing: s.letterSpacing,
      wordSpacing: s.wordSpacing,
      textBaseline: s.textBaseline,
      height: s.height,
      leadingDistribution: s.leadingDistribution,
      decoration: s.decoration,
      decorationColor: s.decorationColor,
      decorationStyle: s.decorationStyle,
      decorationThickness: s.decorationThickness,
      overflow: s.overflow,
      // fontFamily intentionally omitted — null tells the engine to use the
      // platform default typeface, which on Android honours the user's
      // system font setting.
    );
  }

  return TextTheme(
    displayLarge: strip(textTheme.displayLarge),
    displayMedium: strip(textTheme.displayMedium),
    displaySmall: strip(textTheme.displaySmall),
    headlineLarge: strip(textTheme.headlineLarge),
    headlineMedium: strip(textTheme.headlineMedium),
    headlineSmall: strip(textTheme.headlineSmall),
    titleLarge: strip(textTheme.titleLarge),
    titleMedium: strip(textTheme.titleMedium),
    titleSmall: strip(textTheme.titleSmall),
    bodyLarge: strip(textTheme.bodyLarge),
    bodyMedium: strip(textTheme.bodyMedium),
    bodySmall: strip(textTheme.bodySmall),
    labelLarge: strip(textTheme.labelLarge),
    labelMedium: strip(textTheme.labelMedium),
    labelSmall: strip(textTheme.labelSmall),
  );
}

ThemeData buildAppTheme(ColorScheme colorScheme) {
  final theme = ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    cardTheme: CardThemeData(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      color: colorScheme.surfaceContainerHigh,
      shadowColor: colorScheme.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      scrolledUnderElevation: 2,
      backgroundColor: colorScheme.surface,
      surfaceTintColor: colorScheme.surfaceTint,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      surfaceTintColor: colorScheme.surfaceTint,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: colorScheme.inverseSurface,
      contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      labelStyle: const TextStyle(fontSize: 11),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: const DividerThemeData(space: 1),
    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const Icon(Icons.check, size: 16);
        }
        return null;
      }),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      backgroundColor: colorScheme.primaryContainer,
      foregroundColor: colorScheme.onPrimaryContainer,
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: colorScheme.secondaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(
        colorScheme.surfaceContainerHigh,
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: colorScheme.outlineVariant,
      labelColor: colorScheme.primary,
      unselectedLabelColor: colorScheme.onSurfaceVariant,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: colorScheme.surfaceContainerHigh,
      headerBackgroundColor: colorScheme.primaryContainer,
      headerForegroundColor: colorScheme.onPrimaryContainer,
      rangePickerBackgroundColor: colorScheme.surfaceContainerHigh,
      rangePickerHeaderBackgroundColor: colorScheme.primaryContainer,
      rangePickerHeaderForegroundColor: colorScheme.onPrimaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
  );

  // Use the platform's default typeface instead of Material's bundled Roboto,
  // so Android users who set a custom system font see it in the app.
  return theme.copyWith(
    textTheme: _useSystemFont(theme.textTheme),
    primaryTextTheme: _useSystemFont(theme.primaryTextTheme),
  );
}
