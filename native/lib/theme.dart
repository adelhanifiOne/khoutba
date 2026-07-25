import 'package:flutter/material.dart';

/// Palette de l'app, accordée au logo : prune, crème, doré discret.
///
/// Deux nuances distinctes là où le contraste l'impose :
///  - en mode sombre, l'accent des boutons (texte blanc dessus) doit être plus
///    foncé que celui des titres et liens (lus sur fond sombre) ;
///  - le doré décoratif est trop clair pour servir de texte sur fond clair.
/// Toutes les paires ci-dessous ont été vérifiées au niveau AA (≥ 4,5).
class Couleurs {
  // Clair
  static const accent = Color(0xFF5E2751);        // boutons et texte
  static const accentFonce = Color(0xFF3D1836);   // appui, dégradés
  static const creme = Color(0xFFFAF6F3);
  static const carteClaire = Color(0xFFFFFFFF);
  static const or = Color(0xFFC9A227);            // décoratif (filets, bordures)
  static const orTexte = Color(0xFF8A6B12);       // lisible sur fond clair
  static const rouge = Color(0xFFB3382C);

  // Sombre
  static const accentSombre = Color(0xFF9B5A8B);       // boutons
  static const accentTexteSombre = Color(0xFFB87BA8);  // titres, liens
  static const fondSombre = Color(0xFF17111A);
  static const carteSombre = Color(0xFF221A26);
  static const orSombre = Color(0xFFD4B04A);           // lisible sur fond sombre
  static const rougeSombre = Color(0xFFE07B6F);
}

ThemeData themeClair() => _theme(Brightness.light);
ThemeData themeSombre() => _theme(Brightness.dark);

/// Accent réservé au texte (titres, liens) : plus clair en mode sombre.
Color accentTexte(BuildContext contexte) =>
    Theme.of(contexte).brightness == Brightness.dark
        ? Couleurs.accentTexteSombre
        : Couleurs.accent;

/// Doré lisible comme texte, selon le mode.
Color orLisible(BuildContext contexte) =>
    Theme.of(contexte).brightness == Brightness.dark ? Couleurs.orSombre : Couleurs.orTexte;

ThemeData _theme(Brightness luminosite) {
  final sombre = luminosite == Brightness.dark;
  final accent = sombre ? Couleurs.accentSombre : Couleurs.accent;
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
