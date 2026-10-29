import 'package:facture_scanner/core/models/scan_record.dart';
import 'package:facture_scanner/core/providers/auth_provider.dart';
import 'package:facture_scanner/core/providers/scan_provider.dart';
import 'package:facture_scanner/widgets/scan_result_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

ScanRecord _record({String state = 'done'}) => ScanRecord(
  id: 12,
  reference: 'SCAN/2026/0042',
  qrUuid: '0b9d2c1e-1111-2222-3333-444455556666',
  supplierName: 'TERMINAL DE SAN-PEDRO',
  supplierCodeDgi: '1234567A',
  invoiceNumberDgi: '2600123456',
  amountTtc: 1250000,
  documentTypeVerified: true,
  currency: 'XOF',
  state: state,
  stateLabel: 'Terminé',
  scanDate: DateTime(2026, 10, 2, 9, 30),
  scannedBy: 'Awa Koné',
  duplicateCount: 2,
);

/// Ouvre le dialogue et renvoie une fonction qui donne la valeur avec
/// laquelle il a été refermé.
Future<String? Function()> _open(
  WidgetTester tester,
  ScanState state, {
  ScanRecord? record,
  String? message,
  bool showScanAgain = true,
}) async {
  useSmallPhoneScreen(tester);
  String? result = 'non refermé';
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    builder: (_) => ScanResultDialog(
                      state: state,
                      message: message,
                      scanRecord: record,
                      showScanAgain: showScanAgain,
                    ),
                  );
                },
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
  return () => result;
}

void main() {
  setUp(mockPlatformPlugins);

  group('Doublon', () {
    testWidgets('dit qui a déjà scanné la facture, et quand', (tester) async {
      await _open(
        tester,
        ScanState.duplicate,
        record: _record(),
        message: 'Cette facture a déjà été scannée.',
      );

      expect(find.text('Doublon détecté'), findsOneWidget);
      expect(find.text('Tentative #3'), findsOneWidget);
      expect(find.text('Déjà scannée par'), findsOneWidget);
      expect(find.text('Awa Koné'), findsOneWidget);
      expect(find.text('SCAN/2026/0042'), findsOneWidget);
      expect(find.text('Scannée le'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('« Nouveau scan » renvoie scan_again', (tester) async {
      final result = await _open(
        tester,
        ScanState.duplicate,
        record: _record(),
      );
      await tester.tap(find.text('Nouveau scan'));
      await tester.pumpAndSettle();
      expect(result(), 'scan_again');
    });

    testWidgets('« Fermer » ne relance pas de scan', (tester) async {
      final result = await _open(
        tester,
        ScanState.duplicate,
        record: _record(),
      );
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(find.text('Doublon détecté'), findsNothing);
      expect(result(), isNull);
    });
  });

  testWidgets('les boutons restent visibles quand les détails débordent', (
    tester,
  ) async {
    await _open(tester, ScanState.duplicate, record: _record());
    // `tap` échoue (warnIfMissed) si le bouton est hors de l'écran.
    final screen = tester.getRect(find.byType(Scaffold).first);
    for (final label in ['Fermer', 'Nouveau scan']) {
      expect(
        screen.contains(tester.getCenter(find.text(label))),
        isTrue,
        reason: '« $label » doit être visible sans défiler',
      );
    }
  });

  testWidgets('succès : le message ne répète pas le sous-titre', (
    tester,
  ) async {
    await _open(
      tester,
      ScanState.success,
      record: _record(),
      message: 'Facture créée avec succès',
    );
    expect(find.text('Facture enregistrée'), findsOneWidget);
    expect(find.text('Facture créée avec succès'), findsOneWidget);
    expect(find.text('Déjà scannée par'), findsNothing);
  });

  testWidgets('saisie manuelle : bouton dédié qui renvoie manual_entry', (
    tester,
  ) async {
    final result = await _open(
      tester,
      ScanState.manualEntry,
      message: 'Vérification DGI indisponible',
    );
    expect(find.text('Saisie manuelle requise'), findsOneWidget);
    expect(find.text('Plus tard'), findsOneWidget);
    await tester.tap(find.text('Saisir manuellement'));
    await tester.pumpAndSettle();
    expect(result(), 'manual_entry');
  });

  testWidgets('traitement en cours, sans « Nouveau scan » si non proposé', (
    tester,
  ) async {
    await _open(tester, ScanState.processing, showScanAgain: false);
    expect(find.text('Traitement en cours'), findsOneWidget);
    expect(find.text('Nouveau scan'), findsNothing);
    expect(find.text('Fermer'), findsOneWidget);
  });

  testWidgets('erreur : le détail est affiché', (tester) async {
    await _open(tester, ScanState.error, message: 'QR-code illisible');
    expect(find.text('Erreur'), findsOneWidget);
    expect(find.text('QR-code illisible'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
