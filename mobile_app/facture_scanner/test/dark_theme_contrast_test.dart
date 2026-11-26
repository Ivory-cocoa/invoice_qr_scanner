import 'package:facture_scanner/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rapport de contraste WCAG entre deux couleurs opaques.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Lisibilité du mode sombre : chaque couleur de texte ou d'icône doit se
/// détacher nettement des deux fonds de l'application. Ce test échoue si une
/// couleur du thème clair (bleu, vert, rouge profonds) revient en mode sombre.
void main() {
  const surfaces = {
    'fond': AppTheme.darkSurface,
    'carte': AppTheme.darkSurfaceElevated,
  };

  test('texte principal, secondaire et discret', () {
    for (final surface in surfaces.entries) {
      expect(
        contrast(AppTheme.darkTextPrimary, surface.value),
        greaterThan(12),
        reason: 'principal sur ${surface.key}',
      );
      expect(
        contrast(AppTheme.darkTextSecondary, surface.value),
        greaterThan(9),
        reason: 'secondaire sur ${surface.key}',
      );
      expect(
        contrast(AppTheme.darkTextMuted, surface.value),
        greaterThan(6),
        reason: 'discret sur ${surface.key}',
      );
    }
  });

  test('couleurs sémantiques lisibles en texte (au moins 7:1)', () {
    const colors = {
      'primaire': AppTheme.darkPrimaryColor,
      'accent': AppTheme.darkAccentColor,
      'succès': AppTheme.darkSuccessColor,
      'erreur': AppTheme.darkErrorColor,
      'avertissement': AppTheme.darkWarningColor,
      'information': AppTheme.darkInfoColor,
    };
    for (final color in colors.entries) {
      for (final surface in surfaces.entries) {
        expect(
          contrast(color.value, surface.value),
          greaterThan(7),
          reason: '${color.key} sur ${surface.key}',
        );
      }
    }
  });

  test('les couleurs du thème clair ne suffisent pas sur fond sombre', () {
    // Ce qui justifie des couleurs propres au mode sombre.
    expect(
      contrast(AppTheme.primaryColor, AppTheme.darkSurfaceElevated),
      lessThan(4.5),
    );
    expect(
      contrast(AppTheme.errorColor, AppTheme.darkSurfaceElevated),
      lessThan(4.5),
    );
  });

  test(
    'texte posé sur un fond coloré : le meilleur des deux, au moins 4:1',
    () {
      const backgrounds = [
        AppTheme.primaryColor,
        AppTheme.successColor,
        AppTheme.errorColor,
        AppTheme.accentColor,
        AppTheme.darkPrimaryColor,
        AppTheme.darkAccentColor,
        AppTheme.darkSuccessColor,
        AppTheme.darkErrorColor,
        AppTheme.darkWarningColor,
        AppTheme.darkInfoColor,
      ];
      for (final background in backgrounds) {
        final chosen = contrast(AppTheme.onColor(background), background);
        // Jamais moins bien que le blanc, et lisible même sur un ton moyen
        // (sarcelle du thème clair : 4,3:1 au mieux).
        expect(
          chosen,
          greaterThanOrEqualTo(contrast(Colors.white, background)),
          reason: 'fond $background',
        );
        expect(chosen, greaterThan(4), reason: 'fond $background');
      }
    },
  );

  testWidgets('une couleur foncée est éclaircie en mode sombre seulement', (
    tester,
  ) async {
    late Color dark, light;
    Widget probe(ThemeData theme, void Function(Color) out) => MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          out(AppTheme.readable(context, Colors.purple));
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(probe(AppTheme.darkTheme, (c) => dark = c));
    await tester.pumpAndSettle();
    // Nouvelle application (clé différente) : pas de fondu d'un thème à
    // l'autre, qui laisserait le premier affichage encore sombre.
    await tester.pumpWidget(
      KeyedSubtree(
        key: const ValueKey('clair'),
        child: probe(AppTheme.lightTheme, (c) => light = c),
      ),
    );
    await tester.pumpAndSettle();
    expect(light.toARGB32(), Colors.purple.toARGB32());
    expect(contrast(dark, AppTheme.darkSurfaceElevated), greaterThan(4.5));
    expect(
      contrast(Colors.purple, AppTheme.darkSurfaceElevated),
      lessThan(4.5),
    );
  });
}
