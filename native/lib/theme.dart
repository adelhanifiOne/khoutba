import 'package:flutter/material.dart';

/// Palette de l'app : vert de mosquée, crème, doré discret.
class Couleurs {
  static const accent = Color(0xFF0F6B4F);
  static const accentFonce = Color(0xFF0A4F3A);
  static const accentClair = Color(0xFF35A37F);
  static const or = Color(0xFFC9A227);
  static const orSombre = Color(0xFFD4B04A);
  static const creme = Color(0xFFFAF7F0);
  static const carteClaire = Color(0xFFFFFFFF);
  static const fondSombre = Color(0xFF121815);
  static const carteSombre = Color(0xFF1B241F);
  static const rouge = Color(0xFFB3382C);
  static const rougeSombre = Color(0xFFE07B6F);
}

ThemeData themeClair() => _theme(Brightness.light);
ThemeData themeSombre() => _theme(Brightness.dark);

ThemeData _theme(Brightness luminosite) {
  final sombre = luminosite == Brightness.dark;
  final accent = sombre ? Couleurs.accentClair : Couleurs.accent;
  final fond = sombre ? Couleurs.fondSombre : Couleurs.creme;
  final carte = sombre ? Couleurs.carteSombre : Couleurs.carteClaire;

  final base = ThemeData(
    useMaterial3: true,
    brightness: luminosite,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Couleurs.accent,
      brightness: luminosite,
      primary: accent,
      surface: fond,
    ),
    scaffoldBackgroundColor: fond,
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: fond,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: base.colorScheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: carte,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: base.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: base.colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// Style du texte arabe (plus grand, interligne aéré).
TextStyle styleArabe(BuildContext contexte, {double taille = 21}) => TextStyle(
      fontSize: taille,
      height: 2.0,
      color: Theme.of(contexte).colorScheme.onSurface,
    );
