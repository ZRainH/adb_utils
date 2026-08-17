import 'package:flutter/material.dart';

ThemeData buildAppTheme({Brightness brightness = Brightness.dark}) {
  final isDark = brightness == Brightness.dark;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'Segoe UI',
    scaffoldBackgroundColor:
        isDark ? const Color(0xFF121415) : const Color(0xFFF3F5F7),
    colorScheme: isDark
        ? const ColorScheme.dark(
            primary: Color(0xFF006494),
            onPrimary: Color(0xFFB6DDFF),
            surface: Color(0xFF1A1C1D),
            onSurface: Color(0xFFE3E2E4),
            secondary: Color(0xFF8ECDFF),
            error: Color(0xFF93000A),
            onError: Color(0xFFFFDAD6),
            outline: Color(0xFF40484F),
          )
        : const ColorScheme.light(
            primary: Color(0xFF006494),
            onPrimary: Colors.white,
            surface: Color(0xFFFFFFFF),
            onSurface: Color(0xFF1A1C1D),
            secondary: Color(0xFF006494),
            error: Color(0xFF93000A),
            onError: Color(0xFFFFDAD6),
            outline: Color(0xFFC2C7CE),
          ),
  );

  final onSurface = isDark ? const Color(0xFFE3E2E4) : const Color(0xFF1A1C1D);
  final muted = isDark ? const Color(0xFFC0C7D0) : const Color(0xFF5A6169);
  final chip = isDark ? const Color(0xFF333537) : const Color(0xFFE2E6EA);
  final border = isDark ? const Color(0xFF40484F) : const Color(0xFFC2C7CE);

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    ),
    dividerTheme: DividerThemeData(
      color: border,
      thickness: 1,
      space: 1,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: const Color(0xFF006494),
      inactiveTrackColor: chip,
      thumbColor: isDark ? const Color(0xFF8ECDFF) : const Color(0xFF006494),
      overlayColor: const Color(0xFF006494).withValues(alpha: 0.12),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          isDark ? const Color(0xFF1E2021) : Colors.white,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: chip,
      hintStyle: TextStyle(
        color: muted.withValues(alpha: 0.7),
        fontSize: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(999),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return isDark ? const Color(0xFFE3E2E4) : Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const Color(0xFF006494);
        }
        return chip;
      }),
      trackOutlineColor: WidgetStateProperty.all(border),
    ),
  );
}
