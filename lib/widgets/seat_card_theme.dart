import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

// ---------------------------------------------------------------------------
// SeatCardThemeData — all visual tokens for seat cards (all nullable).
// ---------------------------------------------------------------------------

/// Defines the visual properties shared by all seat card variants.
///
/// Every field is nullable; unset values are resolved to sensible defaults
/// from the current [ColorScheme] and [AppColors] when
/// [SeatCardThemeData.resolve] is called.
///
/// To theme an entire subtree of seat cards at once, wrap it with a
/// [SeatCardTheme] widget:
///
/// ```dart
/// SeatCardTheme(
///   data: SeatCardThemeData(borderRadius: 20, avatarRadius: 18),
///   child: MyGrid(...),
/// )
/// ```
@immutable
class SeatCardThemeData {
  const SeatCardThemeData({
    this.borderRadius,
    this.borderWidth,
    this.padding,
    this.engagedBackgroundColor,
    this.engagedBorderColor,
    this.vacantBackgroundColor,
    this.vacantBorderColor,
    this.labelStyle,
    this.engagedBadgeColor,
    this.engagedBadgeTextColor,
    this.vacantBadgeColor,
    this.vacantBadgeTextColor,
    this.badgeTextStyle,
    this.avatarBackgroundColor,
    this.avatarForegroundColor,
    this.avatarRadius,
    this.personNameStyle,
    this.buttonBackgroundColor,
    this.buttonForegroundColor,
  });

  // -- Card shell --
  final double? borderRadius;
  final double? borderWidth;
  final EdgeInsets? padding;

  // -- Background & border per state --
  final Color? engagedBackgroundColor;
  final Color? engagedBorderColor;
  final Color? vacantBackgroundColor;
  final Color? vacantBorderColor;

  // -- Label --
  final TextStyle? labelStyle;

  // -- Status badge (Engaged / Vacant chip) --
  final Color? engagedBadgeColor;
  final Color? engagedBadgeTextColor;
  final Color? vacantBadgeColor;
  final Color? vacantBadgeTextColor;
  final TextStyle? badgeTextStyle;

  // -- Person avatar --
  final Color? avatarBackgroundColor;
  final Color? avatarForegroundColor;
  final double? avatarRadius;

  // -- Person name --
  final TextStyle? personNameStyle;

  // -- Action button (Book) --
  final Color? buttonBackgroundColor;
  final Color? buttonForegroundColor;

  /// Merge [other] on top of this, preferring [other]'s non-null values.
  SeatCardThemeData merge(SeatCardThemeData? other) {
    if (other == null) return this;
    return SeatCardThemeData(
      borderRadius: other.borderRadius ?? borderRadius,
      borderWidth: other.borderWidth ?? borderWidth,
      padding: other.padding ?? padding,
      engagedBackgroundColor:
          other.engagedBackgroundColor ?? engagedBackgroundColor,
      engagedBorderColor: other.engagedBorderColor ?? engagedBorderColor,
      vacantBackgroundColor:
          other.vacantBackgroundColor ?? vacantBackgroundColor,
      vacantBorderColor: other.vacantBorderColor ?? vacantBorderColor,
      labelStyle: other.labelStyle ?? labelStyle,
      engagedBadgeColor: other.engagedBadgeColor ?? engagedBadgeColor,
      engagedBadgeTextColor:
          other.engagedBadgeTextColor ?? engagedBadgeTextColor,
      vacantBadgeColor: other.vacantBadgeColor ?? vacantBadgeColor,
      vacantBadgeTextColor: other.vacantBadgeTextColor ?? vacantBadgeTextColor,
      badgeTextStyle: other.badgeTextStyle ?? badgeTextStyle,
      avatarBackgroundColor:
          other.avatarBackgroundColor ?? avatarBackgroundColor,
      avatarForegroundColor:
          other.avatarForegroundColor ?? avatarForegroundColor,
      avatarRadius: other.avatarRadius ?? avatarRadius,
      personNameStyle: other.personNameStyle ?? personNameStyle,
      buttonBackgroundColor:
          other.buttonBackgroundColor ?? buttonBackgroundColor,
      buttonForegroundColor:
          other.buttonForegroundColor ?? buttonForegroundColor,
    );
  }

  /// Resolve all null fields against [cs] and [isDark] to produce a
  /// fully concrete [ResolvedSeatCardTheme].
  ResolvedSeatCardTheme resolve(ColorScheme cs, bool isDark) {
    return ResolvedSeatCardTheme(
      borderRadius: borderRadius ?? 12.0,
      borderWidth: borderWidth ?? 1.0,
      padding: padding ?? const EdgeInsets.all(12),
      engagedBackgroundColor: engagedBackgroundColor ??
          (isDark
              ? cs.primaryContainer.withValues(alpha: 0.4)
              : cs.primaryContainer),
      engagedBorderColor: engagedBorderColor ?? cs.primary,
      vacantBackgroundColor:
          vacantBackgroundColor ?? AppColors.greenContainer(isDark),
      vacantBorderColor: vacantBorderColor ?? AppColors.greenBorder(isDark),
      labelStyle: labelStyle ??
          const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      engagedBadgeColor:
          engagedBadgeColor ?? cs.error.withValues(alpha: 0.15),
      engagedBadgeTextColor: engagedBadgeTextColor ?? cs.error,
      vacantBadgeColor: vacantBadgeColor ??
          AppColors.greenTextLight.withValues(alpha: 0.15),
      vacantBadgeTextColor: vacantBadgeTextColor ?? AppColors.greenBorderDark,
      badgeTextStyle: badgeTextStyle ??
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      avatarBackgroundColor: avatarBackgroundColor ?? cs.primary,
      avatarForegroundColor: avatarForegroundColor ?? cs.onPrimary,
      avatarRadius: avatarRadius ?? 13.0,
      personNameStyle: personNameStyle ?? const TextStyle(fontSize: 13),
      buttonBackgroundColor:
          buttonBackgroundColor ?? AppColors.greenButtonBg(isDark),
      buttonForegroundColor:
          buttonForegroundColor ?? AppColors.greenButtonFg(isDark),
    );
  }
}

// ---------------------------------------------------------------------------
// ResolvedSeatCardTheme — fully resolved (no nulls) theme.
// ---------------------------------------------------------------------------

/// A fully resolved seat card theme where every property has a concrete value.
///
/// Obtained from [SeatCardThemeData.resolve] or the builder callback in
/// [BaseSeatCard]. Use the convenience getters [backgroundColor],
/// [borderColor], [badgeColor], and [badgeTextColor] to pick the right
/// value for the current engagement state.
@immutable
class ResolvedSeatCardTheme {
  const ResolvedSeatCardTheme({
    required this.borderRadius,
    required this.borderWidth,
    required this.padding,
    required this.engagedBackgroundColor,
    required this.engagedBorderColor,
    required this.vacantBackgroundColor,
    required this.vacantBorderColor,
    required this.labelStyle,
    required this.engagedBadgeColor,
    required this.engagedBadgeTextColor,
    required this.vacantBadgeColor,
    required this.vacantBadgeTextColor,
    required this.badgeTextStyle,
    required this.avatarBackgroundColor,
    required this.avatarForegroundColor,
    required this.avatarRadius,
    required this.personNameStyle,
    required this.buttonBackgroundColor,
    required this.buttonForegroundColor,
  });

  // -- Card shell --
  final double borderRadius;
  final double borderWidth;
  final EdgeInsets padding;

  // -- State colors --
  final Color engagedBackgroundColor;
  final Color engagedBorderColor;
  final Color vacantBackgroundColor;
  final Color vacantBorderColor;

  // -- Label --
  final TextStyle labelStyle;

  // -- Status badge --
  final Color engagedBadgeColor;
  final Color engagedBadgeTextColor;
  final Color vacantBadgeColor;
  final Color vacantBadgeTextColor;
  final TextStyle badgeTextStyle;

  // -- Avatar --
  final Color avatarBackgroundColor;
  final Color avatarForegroundColor;
  final double avatarRadius;

  // -- Person name --
  final TextStyle personNameStyle;

  // -- Action button --
  final Color buttonBackgroundColor;
  final Color buttonForegroundColor;

  // -- Convenience state selectors --

  /// Background color for the given engagement state.
  Color backgroundColor(bool isEngaged) =>
      isEngaged ? engagedBackgroundColor : vacantBackgroundColor;

  /// Border color for the given engagement state.
  Color borderColor(bool isEngaged) =>
      isEngaged ? engagedBorderColor : vacantBorderColor;

  /// Badge background color for the given engagement state.
  Color badgeColor(bool isEngaged) =>
      isEngaged ? engagedBadgeColor : vacantBadgeColor;

  /// Badge text color for the given engagement state.
  Color badgeTextColor(bool isEngaged) =>
      isEngaged ? engagedBadgeTextColor : vacantBadgeTextColor;
}

// ---------------------------------------------------------------------------
// SeatCardTheme — InheritedWidget for ancestor-level theming.
// ---------------------------------------------------------------------------

/// Provides [SeatCardThemeData] to all descendant seat cards.
///
/// Wrap any subtree to customise every seat card underneath it:
///
/// ```dart
/// SeatCardTheme(
///   data: SeatCardThemeData(
///     borderRadius: 20,
///     avatarRadius: 18,
///     vacantBorderColor: Colors.teal,
///   ),
///   child: GridView(...),
/// )
/// ```
class SeatCardTheme extends InheritedWidget {
  const SeatCardTheme({
    super.key,
    required this.data,
    required super.child,
  });

  final SeatCardThemeData data;

  /// Returns the nearest ancestor [SeatCardThemeData], or an empty
  /// (all-defaults) instance if none is found.
  static SeatCardThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SeatCardTheme>()?.data ??
      const SeatCardThemeData();

  @override
  bool updateShouldNotify(SeatCardTheme oldWidget) => data != oldWidget.data;
}
