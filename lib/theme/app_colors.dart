import 'package:flutter/material.dart';

abstract final class AppColors {
  static Brightness _brightness = Brightness.dark;

  static void apply(Brightness b) {
    _brightness = b;
  }

  static void applyThemeMode(ThemeMode mode, Brightness platform) {
    switch (mode) {
      case ThemeMode.light:
        apply(Brightness.light);
      case ThemeMode.dark:
        apply(Brightness.dark);
      case ThemeMode.system:
        apply(platform);
    }
  }

  static bool get _isDark => _brightness == Brightness.dark;

  static Color get background =>
      _isDark ? const Color(0xFF121415) : const Color(0xFFF3F5F7);

  static Color get surface =>
      _isDark ? const Color(0xFF1A1C1D) : const Color(0xFFFFFFFF);

  static Color get surfaceElevated =>
      _isDark ? const Color(0xFF1E2021) : const Color(0xFFFFFFFF);

  static Color get surfaceMuted =>
      _isDark ? const Color(0xFF292A2C) : const Color(0xFFE2E6EA);

  static Color get surfaceDeep =>
      _isDark ? const Color(0xFF0D0E10) : const Color(0xFFE8EAED);

  static Color get chip =>
      _isDark ? const Color(0xFF333537) : const Color(0xFFE2E6EA);

  static Color get border =>
      _isDark ? const Color(0xFF40484F) : const Color(0xFFC2C7CE);

  static Color get borderSoft =>
      _isDark ? const Color(0x4D40484F) : const Color(0x4DC2C7CE);

  static Color get textPrimary =>
      _isDark ? const Color(0xFFE3E2E4) : const Color(0xFF1A1C1D);

  static Color get textSecondary =>
      _isDark ? const Color(0xFFC0C7D0) : const Color(0xFF5A6169);

  static Color get textMuted =>
      _isDark ? const Color(0xFFB9C9D5) : const Color(0xFF6B7380);

  static Color get accent => const Color(0xFF006494);

  static Color get accentBright =>
      _isDark ? const Color(0xFF8ECDFF) : const Color(0xFF006494);

  static Color get accentOn =>
      _isDark ? const Color(0xFFB6DDFF) : const Color(0xFFFFFFFF);

  static Color get accentDark => const Color(0xFF00344F);

  static Color get danger => const Color(0xFF93000A);

  static Color get dangerOn => const Color(0xFFFFDAD6);

  static Color get warning =>
      _isDark ? const Color(0xFFE6C07B) : const Color(0xFF9A6700);

  static Color get errorLog =>
      _isDark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A);

  static Color get debugLog =>
      _isDark ? const Color(0xFF8ECDFF) : const Color(0xFF006494);

  static Color get infoLog =>
      _isDark ? const Color(0xFFB9C9D5) : const Color(0xFF5A6169);

  static Color get verboseLog =>
      _isDark ? const Color(0xFFC0C7D0) : const Color(0xFF6B7380);

  static Color get memorySystem => const Color(0xFFE57373);

  static Color get memoryApps =>
      _isDark ? const Color(0xFF8ECDFF) : const Color(0xFF006494);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color _of(BuildContext context, Color Function() getter) {
    apply(Theme.of(context).brightness);
    return getter();
  }

  static Color backgroundOf(BuildContext context) =>
      _of(context, () => background);

  static Color surfaceOf(BuildContext context) => _of(context, () => surface);

  static Color surfaceElevatedOf(BuildContext context) =>
      _of(context, () => surfaceElevated);

  static Color surfaceMutedOf(BuildContext context) =>
      _of(context, () => surfaceMuted);

  static Color surfaceDeepOf(BuildContext context) =>
      _of(context, () => surfaceDeep);

  static Color chipOf(BuildContext context) => _of(context, () => chip);

  static Color borderOf(BuildContext context) => _of(context, () => border);

  static Color borderSoftOf(BuildContext context) =>
      _of(context, () => borderSoft);

  static Color textPrimaryOf(BuildContext context) =>
      _of(context, () => textPrimary);

  static Color textSecondaryOf(BuildContext context) =>
      _of(context, () => textSecondary);

  static Color textMutedOf(BuildContext context) =>
      _of(context, () => textMuted);

  static Color accentOf(BuildContext context) => _of(context, () => accent);

  static Color accentBrightOf(BuildContext context) =>
      _of(context, () => accentBright);

  static Color accentOnOf(BuildContext context) =>
      _of(context, () => accentOn);

  static Color accentDarkOf(BuildContext context) =>
      _of(context, () => accentDark);

  static Color dangerOf(BuildContext context) => _of(context, () => danger);

  static Color dangerOnOf(BuildContext context) =>
      _of(context, () => dangerOn);

  static Color warningOf(BuildContext context) => _of(context, () => warning);

  static Color errorLogOf(BuildContext context) =>
      _of(context, () => errorLog);

  static Color debugLogOf(BuildContext context) =>
      _of(context, () => debugLog);

  static Color infoLogOf(BuildContext context) => _of(context, () => infoLog);

  static Color verboseLogOf(BuildContext context) =>
      _of(context, () => verboseLog);

  static Color memorySystemOf(BuildContext context) =>
      _of(context, () => memorySystem);

  static Color memoryAppsOf(BuildContext context) =>
      _of(context, () => memoryApps);
}
