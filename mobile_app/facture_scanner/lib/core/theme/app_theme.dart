/// App Theme Configuration - Design Professionnel ICP
/// Thème moderne avec excellent contraste et lisibilité
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // ═══════════════════════════════════════════════════════════════════════════
  // PALETTE DE COULEURS PROFESSIONNELLES
  // ═══════════════════════════════════════════════════════════════════════════

  // Couleurs primaires - Bleu professionnel ICP
  static const Color primaryColor = Color(0xFF1565C0); // Bleu principal
  static const Color primaryDark = Color(0xFF0D47A1); // Bleu foncé
  static const Color primaryLight = Color(0xFF42A5F5); // Bleu clair
  static const Color primarySurface = Color(
    0xFFE3F2FD,
  ); // Bleu très léger (fond)

  // Couleurs d'accent
  static const Color accentColor = Color(0xFF00897B); // Teal professionnel
  static const Color accentLight = Color(0xFF4DB6AC); // Teal clair

  // Couleurs sémantiques
  static const Color successColor = Color(0xFF2E7D32); // Vert succès
  static const Color successLight = Color(0xFFE8F5E9); // Fond succès
  static const Color errorColor = Color(0xFFC62828); // Rouge erreur
  static const Color errorLight = Color(0xFFFFEBEE); // Fond erreur
  static const Color warningColor = Color(0xFFEF6C00); // Orange avertissement
  static const Color warningLight = Color(0xFFFFF3E0); // Fond avertissement
  static const Color infoColor = Color(0xFF0277BD); // Bleu info
  static const Color infoLight = Color(0xFFE1F5FE); // Fond info

  // Couleurs de texte - EXCELLENT CONTRASTE (WCAG AAA)
  static const Color textDark = Color(0xFF1A1A1A); // Texte principal (noir)
  static const Color textMedium = Color(0xFF424242); // Texte secondaire
  static const Color textLight = Color(0xFF757575); // Texte désactivé
  static const Color textOnPrimary = Colors.white; // Texte sur fond primaire
  static const Color textOnDark = Colors.white; // Texte sur fond sombre

  // Alias pour compatibilité
  static const Color textPrimary = textDark; // Alias pour textDark
  static const Color textSecondary = textMedium; // Alias pour textMedium
  static const Color textMuted = textLight; // Alias pour textLight

  // Couleurs de surface
  static const Color surfaceWhite = Colors.white;
  static const Color surfaceLight = Color(0xFFF8F9FA); // Fond principal
  static const Color surfaceMedium = Color(0xFFECEFF1); // Séparateurs
  static const Color dividerColor = Color(0xFFE0E0E0);

  // Gradients professionnels
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1976D2), Color(0xFF0D47A1)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00897B), Color(0xFF004D40)],
  );

  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1A237E), Color(0xFF0D47A1)],
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // TYPOGRAPHIE
  // ═══════════════════════════════════════════════════════════════════════════

  static const String fontFamily = 'Roboto';

  // Les styles de titre et de texte courant ne fixent PAS de couleur : ils
  // prennent celle du thème (sombre sur fond clair, claire sur fond sombre).
  // Une couleur noire figée ici rendait les titres des fenêtres illisibles
  // en mode sombre.
  static const TextStyle headingLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.2,
  );

  static const TextStyle headingMedium = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.3,
  );

  static const TextStyle headingSmall = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle titleLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textMedium,
    height: 1.5,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textLight,
    height: 1.4,
  );

  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textMedium,
    height: 1.3,
  );

  // Style pour le texte de saisie (INPUT)
  static const TextStyle inputText = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: primaryDark, // BLEU FONCÉ sur fond blanc
    height: 1.4,
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // DIMENSIONS ET ESPACEMENTS
  // ═══════════════════════════════════════════════════════════════════════════

  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 24.0;

  static const double spacingXSmall = 4.0;
  static const double spacingSmall = 8.0;
  static const double spacingMedium = 16.0;
  static const double spacingLarge = 24.0;
  static const double spacingXLarge = 32.0;

  static const double elevationLow = 2.0;
  static const double elevationMedium = 4.0;
  static const double elevationHigh = 8.0;

  // ═══════════════════════════════════════════════════════════════════════════
  // DECORATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  static BoxDecoration cardDecoration = BoxDecoration(
    color: surfaceWhite,
    borderRadius: BorderRadius.circular(radiusMedium),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.08),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );

  static BoxDecoration gradientCardDecoration = BoxDecoration(
    gradient: primaryGradient,
    borderRadius: BorderRadius.circular(radiusMedium),
    boxShadow: [
      BoxShadow(
        color: primaryColor.withValues(alpha: 0.3),
        blurRadius: 12,
        offset: const Offset(0, 6),
      ),
    ],
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // THÈME CLAIR (PRINCIPAL)
  // ═══════════════════════════════════════════════════════════════════════════

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    brightness: Brightness.light,

    // Couleurs principales
    colorScheme: const ColorScheme.light(
      primary: primaryColor,
      onPrimary: textOnPrimary,
      primaryContainer: primarySurface,
      secondary: accentColor,
      onSecondary: textOnPrimary,
      error: errorColor,
      onError: textOnPrimary,
      surface: surfaceWhite,
      onSurface: textDark,
      surfaceContainerHighest: surfaceLight,
    ),

    primaryColor: primaryColor,
    scaffoldBackgroundColor: surfaceLight,

    // AppBar moderne
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryColor,
      foregroundColor: textOnPrimary,
      elevation: 0,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      titleTextStyle: TextStyle(
        color: textOnPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
      ),
      iconTheme: IconThemeData(color: textOnPrimary, size: 24),
    ),

    // Textes
    textTheme: const TextTheme(
      displayLarge: headingLarge,
      displayMedium: headingMedium,
      displaySmall: headingSmall,
      headlineLarge: headingLarge,
      headlineMedium: headingMedium,
      headlineSmall: headingSmall,
      titleLarge: titleLarge,
      titleMedium: titleMedium,
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textDark,
      ),
      bodyLarge: bodyLarge,
      bodyMedium: bodyMedium,
      bodySmall: bodySmall,
      labelLarge: labelLarge,
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textMedium,
      ),
      labelSmall: caption,
    ),

    // Boutons élevés
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: textOnPrimary,
        elevation: elevationLow,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    ),

    // Boutons texte
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),

    // Boutons contour
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        side: const BorderSide(color: primaryColor, width: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),

    // Champs de saisie - TEXTE BLEU SUR FOND BLANC
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceWhite,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),

      // Labels et hints
      labelStyle: const TextStyle(
        color: textMedium,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      floatingLabelStyle: const TextStyle(
        color: primaryColor,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: textLight.withValues(alpha: 0.7),
        fontSize: 15,
      ),

      // Préfixe/Suffixe
      prefixIconColor: primaryColor,
      suffixIconColor: textMedium,

      // Bordures
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: dividerColor, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: BorderSide(
          color: dividerColor.withValues(alpha: 0.8),
          width: 1.5,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: errorColor, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: errorColor, width: 2),
      ),

      // Erreurs
      errorStyle: const TextStyle(
        color: errorColor,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),

    // Cards
    cardTheme: CardThemeData(
      elevation: elevationLow,
      color: surfaceWhite,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      margin: const EdgeInsets.symmetric(vertical: spacingSmall),
    ),

    // Lists
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(
        horizontal: spacingMedium,
        vertical: spacingSmall,
      ),
      titleTextStyle: TextStyle(
        color: textDark,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: TextStyle(
        color: textMedium,
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      iconColor: primaryColor,
    ),

    // Chips
    chipTheme: ChipThemeData(
      backgroundColor: surfaceLight,
      labelStyle: const TextStyle(
        color: textDark,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      selectedColor: primarySurface,
      secondarySelectedColor: primarySurface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSmall),
      ),
    ),

    // Dialogs
    dialogTheme: DialogThemeData(
      backgroundColor: surfaceWhite,
      elevation: elevationHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLarge),
      ),
      titleTextStyle: headingSmall,
      contentTextStyle: bodyLarge,
    ),

    // FAB
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: textOnPrimary,
      elevation: elevationMedium,
      shape: StadiumBorder(),
      extendedTextStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),

    // Bottom Navigation
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surfaceWhite,
      selectedItemColor: primaryColor,
      unselectedItemColor: textLight,
      selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 12),
      elevation: 8,
      type: BottomNavigationBarType.fixed,
    ),

    // TabBar
    tabBarTheme: const TabBarThemeData(
      labelColor: textOnPrimary,
      unselectedLabelColor: Colors.white70,
      indicatorColor: textOnPrimary,
      labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
    ),

    // Divider
    dividerTheme: const DividerThemeData(
      color: dividerColor,
      thickness: 1,
      space: 1,
    ),

    // SnackBar
    snackBarTheme: SnackBarThemeData(
      backgroundColor: textDark,
      contentTextStyle: const TextStyle(color: textOnDark, fontSize: 14),
      actionTextColor: primaryLight,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSmall),
      ),
    ),

    // Progress Indicators
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primaryColor,
      linearTrackColor: primarySurface,
    ),

    // Switch
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primaryColor;
        return textLight;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primarySurface;
        return dividerColor;
      }),
    ),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // COULEURS MODE SOMBRE
  // ═══════════════════════════════════════════════════════════════════════════

  // Surfaces sombres
  static const Color darkSurface = Color(0xFF121212);
  static const Color darkSurfaceElevated = Color(0xFF1E1E1E);
  static const Color darkSurfaceHigher = Color(0xFF2C2C2C);
  static const Color darkDivider = Color(0xFF4A4A4A);

  // Texte en mode sombre.
  //
  // Contraste mesuré sur la surface des cartes (#1E1E1E), la plus claire
  // des deux fonds : principal 14,9:1, secondaire 10,4:1, discret 6,7:1.
  // L'ancien « discret » (#808080) tombait à 4,2:1 : les dates, légendes et
  // libellés de second rang se lisaient mal.
  static const Color darkTextPrimary = Color(0xFFF2F2F2);
  static const Color darkTextSecondary = Color(0xFFCFCFCF);
  static const Color darkTextMuted = Color(0xFFA6A6A6);

  // Couleurs sémantiques du mode sombre : versions CLAIRES des couleurs du
  // thème clair, lisibles en texte et en icône sur fond sombre (toutes
  // au-dessus de 7:1 sur #1E1E1E). Les couleurs du thème clair (bleu
  // #1565C0, vert #2E7D32, rouge #C62828, sarcelle #00897B) y descendaient
  // entre 3:1 et 4:1.
  static const Color darkPrimaryColor = Color(0xFF82B1FF);
  static const Color darkPrimarySurface = Color(0xFF1B2B45);
  static const Color darkAccentColor = Color(0xFF64D8CB);
  static const Color darkSuccessColor = Color(0xFF81C784);
  static const Color darkSuccessLight = Color(0xFF1E3A22);
  static const Color darkErrorColor = Color(0xFFFF8A80);
  static const Color darkErrorLight = Color(0xFF45201F);
  static const Color darkWarningColor = Color(0xFFFFC46B);
  static const Color darkWarningLight = Color(0xFF40311A);
  static const Color darkInfoColor = Color(0xFF6FD0FF);
  static const Color darkInfoLight = Color(0xFF17323F);

  // ═══════════════════════════════════════════════════════════════════════════
  // THÈME SOMBRE COMPLET
  // ═══════════════════════════════════════════════════════════════════════════

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: fontFamily,

    // Couleurs principales en mode sombre
    colorScheme: const ColorScheme.dark(
      primary: primaryLight,
      onPrimary: Color(0xFF1A1A1A),
      primaryContainer: primaryDark,
      secondary: accentLight,
      onSecondary: Color(0xFF1A1A1A),
      secondaryContainer: accentColor,
      surface: darkSurface,
      onSurface: darkTextPrimary,
      surfaceContainerHighest: darkSurfaceElevated,
      error: darkErrorColor,
      onError: Colors.white,
    ),

    primaryColor: primaryLight,
    scaffoldBackgroundColor: darkSurface,

    // AppBar sombre avec gradient
    appBarTheme: const AppBarTheme(
      backgroundColor: darkSurfaceElevated,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
      ),
      iconTheme: IconThemeData(color: Colors.white, size: 24),
    ),

    // Textes sombres
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: darkTextPrimary,
        letterSpacing: -0.5,
        height: 1.2,
      ),
      displayMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: darkTextPrimary,
        letterSpacing: -0.3,
        height: 1.3,
      ),
      displaySmall: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: darkTextPrimary,
        height: 1.3,
      ),
      headlineLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: darkTextPrimary,
        letterSpacing: -0.5,
        height: 1.2,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: darkTextPrimary,
        letterSpacing: -0.3,
        height: 1.3,
      ),
      headlineSmall: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: darkTextPrimary,
        height: 1.3,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: darkTextPrimary,
        height: 1.4,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: darkTextPrimary,
        height: 1.4,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: darkTextPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: darkTextPrimary,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: darkTextSecondary,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: darkTextMuted,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: darkTextPrimary,
        letterSpacing: 0.5,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: darkTextSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: darkTextSecondary,
        height: 1.3,
      ),
    ),

    // Boutons élevés sombres
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryLight,
        foregroundColor: Color(0xFF1A1A1A),
        elevation: elevationLow,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    ),

    // Boutons texte sombres
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryLight,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),

    // Boutons contour sombres
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryLight,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        side: const BorderSide(color: primaryLight, width: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),

    // Champs de saisie sombres
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkSurfaceElevated,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),

      // Labels et hints
      labelStyle: const TextStyle(
        color: darkTextSecondary,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      floatingLabelStyle: const TextStyle(
        color: primaryLight,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: darkTextMuted.withValues(alpha: 0.7),
        fontSize: 15,
      ),

      // Préfixe/Suffixe
      prefixIconColor: primaryLight,
      suffixIconColor: darkTextSecondary,

      // Bordures
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: darkDivider, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: BorderSide(
          color: darkDivider.withValues(alpha: 0.8),
          width: 1.5,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: primaryLight, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: darkErrorColor, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
        borderSide: const BorderSide(color: darkErrorColor, width: 2),
      ),

      // Erreurs
      errorStyle: const TextStyle(
        color: darkErrorColor,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),

    // Cards sombres
    cardTheme: CardThemeData(
      elevation: elevationLow,
      color: darkSurfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      margin: const EdgeInsets.symmetric(vertical: spacingSmall),
    ),

    // Lists sombres
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(
        horizontal: spacingMedium,
        vertical: spacingSmall,
      ),
      titleTextStyle: TextStyle(
        color: darkTextPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: TextStyle(
        color: darkTextSecondary,
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      iconColor: primaryLight,
    ),

    // Chips sombres
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? darkPrimaryColor
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Color(0xFF10151C)
              : darkTextPrimary,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: darkDivider)),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: darkSurfaceHigher,
      labelStyle: const TextStyle(
        color: darkTextPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      // Pastille choisie : fond bleu clair, texte foncé (10:1). L'ancien
      // fond bleu nuit sous un texte gris se lisait mal.
      selectedColor: darkPrimaryColor,
      secondarySelectedColor: darkPrimaryColor,
      secondaryLabelStyle: const TextStyle(
        color: Color(0xFF10151C),
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      checkmarkColor: const Color(0xFF10151C),
      side: const BorderSide(color: darkDivider),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSmall),
      ),
    ),

    // Dialogs sombres
    dialogTheme: DialogThemeData(
      backgroundColor: darkSurfaceElevated,
      elevation: elevationHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLarge),
      ),
      titleTextStyle: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: darkTextPrimary,
        height: 1.3,
      ),
      contentTextStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: darkTextPrimary,
        height: 1.5,
      ),
    ),

    // FAB sombre
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryLight,
      foregroundColor: Color(0xFF1A1A1A),
      elevation: elevationMedium,
      shape: StadiumBorder(),
      extendedTextStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),

    // Bottom Navigation sombre
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: darkSurfaceElevated,
      selectedItemColor: primaryLight,
      unselectedItemColor: darkTextMuted,
      selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 12),
      elevation: 8,
      type: BottomNavigationBarType.fixed,
    ),

    // TabBar sombre
    tabBarTheme: const TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white60,
      indicatorColor: primaryLight,
      labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
    ),

    // Divider sombre
    dividerTheme: const DividerThemeData(
      color: darkDivider,
      thickness: 1,
      space: 1,
    ),

    // SnackBar sombre
    snackBarTheme: SnackBarThemeData(
      backgroundColor: darkSurfaceHigher,
      contentTextStyle: const TextStyle(color: darkTextPrimary, fontSize: 14),
      actionTextColor: primaryLight,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSmall),
      ),
    ),

    // Progress Indicators sombre
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primaryLight,
      linearTrackColor: darkSurfaceHigher,
    ),

    // Switch sombre
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primaryLight;
        return darkTextMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primaryDark;
        return darkDivider;
      }),
    ),

    // Checkbox sombre
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primaryLight;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(const Color(0xFF1A1A1A)),
      side: const BorderSide(color: darkTextSecondary, width: 2),
    ),

    // PopupMenu sombre
    popupMenuTheme: PopupMenuThemeData(
      color: darkSurfaceElevated,
      elevation: elevationMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMedium),
      ),
      textStyle: const TextStyle(color: darkTextPrimary, fontSize: 14),
    ),

    // IconButton sombre
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: darkTextPrimary),
    ),
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Retourne la couleur de statut appropriée
  static Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'success':
      case 'validated':
      case 'done':
        return successColor;
      case 'error':
      case 'failed':
        return errorColor;
      case 'warning':
      case 'pending':
        return warningColor;
      case 'info':
      case 'draft':
        return infoColor;
      default:
        return textMedium;
    }
  }

  /// Retourne le fond de statut approprié
  static Color getStatusBackground(String status) {
    switch (status.toLowerCase()) {
      case 'success':
      case 'validated':
      case 'done':
        return successLight;
      case 'error':
      case 'failed':
        return errorLight;
      case 'warning':
      case 'pending':
        return warningLight;
      case 'info':
      case 'draft':
        return infoLight;
      default:
        return surfaceLight;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS ADAPTATIFS (Mode clair/sombre)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Vérifie si le thème actuel est sombre
  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  /// Couleur de texte principale adaptée au thème
  static Color getTextPrimary(BuildContext context) {
    return isDark(context) ? darkTextPrimary : textDark;
  }

  /// Couleur de texte secondaire adaptée au thème
  static Color getTextSecondary(BuildContext context) {
    return isDark(context) ? darkTextSecondary : textMedium;
  }

  /// Couleur de texte muet adaptée au thème
  static Color getTextMuted(BuildContext context) {
    return isDark(context) ? darkTextMuted : textLight;
  }

  /// Couleur de surface principale adaptée au thème
  static Color getSurface(BuildContext context) {
    return isDark(context) ? darkSurface : surfaceWhite;
  }

  /// Couleur de surface élevée adaptée au thème
  static Color getSurfaceElevated(BuildContext context) {
    return isDark(context) ? darkSurfaceElevated : surfaceWhite;
  }

  /// Couleur de surface légère adaptée au thème
  static Color getSurfaceLight(BuildContext context) {
    return isDark(context) ? darkSurfaceHigher : surfaceLight;
  }

  /// Couleur de divider adaptée au thème
  static Color getDivider(BuildContext context) {
    return isDark(context) ? darkDivider : dividerColor;
  }

  /// Couleur de succès adaptée au thème
  static Color getSuccess(BuildContext context) {
    return isDark(context) ? darkSuccessColor : successColor;
  }

  /// Fond de succès adapté au thème
  static Color getSuccessLight(BuildContext context) {
    return isDark(context) ? darkSuccessLight : successLight;
  }

  /// Couleur d'erreur adaptée au thème
  static Color getError(BuildContext context) {
    return isDark(context) ? darkErrorColor : errorColor;
  }

  /// Fond d'erreur adapté au thème
  static Color getErrorLight(BuildContext context) {
    return isDark(context) ? darkErrorLight : errorLight;
  }

  /// Couleur d'avertissement adaptée au thème
  static Color getWarning(BuildContext context) {
    return isDark(context) ? darkWarningColor : warningColor;
  }

  /// Fond d'avertissement adapté au thème
  static Color getWarningLight(BuildContext context) {
    return isDark(context) ? darkWarningLight : warningLight;
  }

  /// Couleur d'info adaptée au thème
  static Color getInfo(BuildContext context) {
    return isDark(context) ? darkInfoColor : infoColor;
  }

  /// Fond d'info adapté au thème
  static Color getInfoLight(BuildContext context) {
    return isDark(context) ? darkInfoLight : infoLight;
  }

  /// Couleur primaire adaptée au thème
  static Color getPrimary(BuildContext context) {
    return isDark(context) ? darkPrimaryColor : primaryColor;
  }

  /// Fond teinté de la couleur primaire, adapté au thème
  static Color getPrimarySurface(BuildContext context) {
    return isDark(context) ? darkPrimarySurface : primarySurface;
  }

  /// Violet « traité » adapté au thème (indigo sur clair, lavande sur sombre)
  static Color getProcessed(BuildContext context) {
    return isDark(context) ? const Color(0xFFB3BCF5) : const Color(0xFF5C6BC0);
  }

  /// Orange « à traiter » adapté au thème
  static Color getPending(BuildContext context) {
    return isDark(context) ? darkWarningColor : const Color(0xFFFF8F00);
  }

  /// Couleur d'accent (sarcelle) adaptée au thème
  static Color getAccent(BuildContext context) {
    return isDark(context) ? darkAccentColor : accentColor;
  }

  /// Fond d'une barre de titre ou d'un bandeau portant un texte BLANC : bleu
  /// soutenu dans les deux thèmes (blanc dessus : 5,9:1). La couleur primaire
  /// du mode sombre, claire, est faite pour le texte, pas pour ce rôle.
  static Color getHeader(BuildContext context) {
    return isDark(context) ? primaryColor : primaryColor;
  }

  /// Rend [color] lisible comme texte ou icône sur le fond du thème : en
  /// mode sombre, une couleur trop foncée (violet, rouge, bleu profond) est
  /// éclaircie. En mode clair, elle est rendue telle quelle.
  static Color readable(BuildContext context, Color color) {
    if (!isDark(context) || color.computeLuminance() >= 0.32) return color;
    return Color.lerp(color, Colors.white, 0.5)!;
  }

  /// Couleur de texte à poser SUR [background] : sombre sur un fond clair,
  /// blanche sur un fond foncé. À utiliser pour un bouton ou une pastille
  /// dont le fond suit le thème.
  static Color onColor(Color background) {
    // Celui des deux, sombre ou blanc, qui contraste le plus avec le fond.
    const dark = Color(0xFF10151C);
    final l = background.computeLuminance();
    final withWhite = 1.05 / (l + 0.05);
    final withDark = (l + 0.05) / (dark.computeLuminance() + 0.05);
    return withDark > withWhite ? dark : Colors.white;
  }

  /// Décoration de carte adaptée au thème
  static BoxDecoration getCardDecoration(BuildContext context) {
    return BoxDecoration(
      color: getSurfaceElevated(context),
      borderRadius: BorderRadius.circular(radiusMedium),
      boxShadow: [
        BoxShadow(
          color: isDark(context)
              ? Colors.black.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.08),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  /// Décoration de carte avec gradient adaptée au thème
  static BoxDecoration getGradientCardDecoration(BuildContext context) {
    if (isDark(context)) {
      return BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
        ),
        borderRadius: BorderRadius.circular(radiusMedium),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      );
    }
    return gradientCardDecoration;
  }
}
