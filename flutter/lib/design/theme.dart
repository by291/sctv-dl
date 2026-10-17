import 'package:flutter/material.dart';

ThemeData buildAppTheme(Brightness brightness, {ColorScheme? dynamicScheme}) {
  final dark = brightness == Brightness.dark;
  final scheme =
      dynamicScheme ??
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF6BAAD9),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xFFA8CEEC) : const Color(0xFF326C96),
        onPrimary: dark ? const Color(0xFF15374E) : Colors.white,
        primaryContainer: dark
            ? const Color(0xFF22455F)
            : const Color(0xFFD3E9FA),
        onPrimaryContainer: dark
            ? const Color(0xFFD3E9FA)
            : const Color(0xFF1E4866),
        secondary: dark ? const Color(0xFFA9AEB8) : const Color(0xFF667080),
        onSecondary: dark ? const Color(0xFF242A33) : Colors.white,
        secondaryContainer: dark
            ? const Color(0xFF293F50)
            : const Color(0xFFDDECF7),
        onSecondaryContainer: dark
            ? const Color(0xFFE7E9EE)
            : const Color(0xFF242A33),
        surface: dark ? const Color(0xFF16191E) : const Color(0xFFF6F7F9),
        onSurface: dark ? const Color(0xFFE7E9EE) : const Color(0xFF242A33),
        surfaceContainerLowest: dark ? const Color(0xFF111419) : Colors.white,
        surfaceContainerLow: dark ? const Color(0xFF1E2229) : Colors.white,
        surfaceContainer: dark
            ? const Color(0xFF262B33)
            : const Color(0xFFF0F2F5),
        surfaceContainerHigh: dark
            ? const Color(0xFF2B3039)
            : const Color(0xFFE8EBEF),
        surfaceContainerHighest: dark
            ? const Color(0xFF343A45)
            : const Color(0xFFEFF1F4),
        onSurfaceVariant: dark
            ? const Color(0xFFA9AEB8)
            : const Color(0xFF667080),
        outline: const Color(0xFF858C99),
        outlineVariant: dark
            ? const Color(0xFF343A45)
            : const Color(0xFFE1E5EB),
      );
  final iconColour =
      dynamicScheme?.primary ??
      (dark ? const Color(0xFFA8CEEC) : const Color(0xFF4C87B3));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    iconTheme: IconThemeData(color: iconColour),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      iconTheme: IconThemeData(color: iconColour),
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? iconColour
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      dividerColor: scheme.outlineVariant,
      labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: .5),
    ),
  );
}
