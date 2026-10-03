// Bandeau de mise à jour (fichier commun aux applications ICP).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facture_scanner/core/services/apk_update.dart';

void main() {
  test('lit la réponse d\'Odoo (url ou download_url) et compare les versions', () {
    final update = ApkUpdate.fromMap({
      'version': '2.1.0',
      'version_code': 4,
      'download_url': 'https://odoo.test/m/app/jeton',
      'sha256': 'ABCDEF',
      'file_size': 41943040,
    })!;
    expect(update.url, 'https://odoo.test/m/app/jeton');
    expect(update.sha256, 'abcdef'); // comparé en minuscules
    expect(update.isNewerThan(3), isTrue);
    expect(update.isNewerThan(4), isFalse);
    expect(ApkUpdate.fromMap({'version': '2.1.0', 'version_code': 4}), isNull); // sans lien
    expect(ApkUpdate.fromMap(false), isNull);
  });

  Future<void> pumpBanner(WidgetTester tester, int current) => tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UpdateBanner(
            update: const ApkUpdate(version: '2.1.0', versionCode: 4, url: 'https://odoo.test/x', fileSize: 41943040),
            currentVersionCode: current,
            updater: ApkUpdater(),
            appName: 'ICP',
          ),
        ),
      ));

  testWidgets('le bandeau n\'apparaît que pour une version plus récente', (tester) async {
    await pumpBanner(tester, 3);
    expect(find.text('Nouvelle version 2.1.0 disponible'), findsOneWidget);
    expect(find.text('Mettre à jour'), findsOneWidget);
    expect(find.textContaining('40,0\u00a0Mo'), findsOneWidget);
    await pumpBanner(tester, 4);
    expect(find.text('Nouvelle version 2.1.0 disponible'), findsNothing);
  });
}
