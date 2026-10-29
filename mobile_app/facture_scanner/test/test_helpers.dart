/// Outils communs aux tests de widgets.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Neutralise les plugins natifs appelés au démarrage d'[AuthProvider]
/// (stockage sécurisé, préférences), absents de l'environnement de test.
void mockPlatformPlugins() {
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (_) async => null,
  );
}

/// Écran d'un téléphone Android courant (360 × 690 dp) : les défauts de mise
/// en page (boutons hors écran) n'apparaissent pas sur l'écran de test par
/// défaut, plus grand.
void useSmallPhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(360 * 3, 690 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}
