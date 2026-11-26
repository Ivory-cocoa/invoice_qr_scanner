import 'package:facture_scanner/widgets/same_number_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

const _warning =
    'ATTENTION — même numéro de facture. La facture n° 2600123456 de ce '
    'fournisseur est déjà enregistré(e) dans Odoo (SCAN/2026/0007).';

/// Ouvre la confirmation et renvoie une fonction qui donne la réponse.
Future<bool? Function()> _open(WidgetTester tester) async {
  useSmallPhoneScreen(tester);
  bool? answer;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                answer = await showSameNumberConfirmDialog(context, _warning);
              },
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
  return () => answer;
}

void main() {
  testWidgets('l\'avertissement du serveur est affiché en entier', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text(_warning), findsOneWidget);
    expect(find.text('Même numéro de facture'), findsOneWidget);
    // Les deux boutons tiennent sur un petit écran.
    expect(tester.takeException(), isNull);
  });

  testWidgets('« Transmettre quand même » confirme', (tester) async {
    final answer = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('same-number-confirm')));
    await tester.pumpAndSettle();
    expect(answer(), isTrue);
  });

  testWidgets('« Ne pas traiter » renonce', (tester) async {
    final answer = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('same-number-cancel')));
    await tester.pumpAndSettle();
    expect(answer(), isFalse);
  });

  testWidgets('toucher à côté ne confirme pas', (tester) async {
    final answer = await _open(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    // La fenêtre reste ouverte : aucune réponse, donc aucun traitement.
    expect(answer(), isNull);
    expect(find.text(_warning), findsOneWidget);
  });
}
