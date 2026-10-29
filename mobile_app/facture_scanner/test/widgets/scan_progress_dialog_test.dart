import 'package:facture_scanner/widgets/scan_progress_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// L'indicateur tourne sans fin : `pumpAndSettle` ne rendrait jamais la main.
const _frame = Duration(milliseconds: 500);

Future<(BuildContext, NavigatorState)> _pumpHome(WidgetTester tester) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  late BuildContext homeContext;
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: Builder(
        builder: (context) {
          homeContext = context;
          return const Scaffold(body: Text('accueil'));
        },
      ),
    ),
  );
  return (homeContext, navigatorKey.currentState!);
}

void main() {
  testWidgets('affiche puis met à jour son message', (tester) async {
    final (context, _) = await _pumpHome(tester);
    final progress = ScanProgress.show(context, 'Recherche de doublons...');
    await tester.pump(_frame);
    expect(find.text('Recherche de doublons...'), findsOneWidget);
    expect(find.text('Continuer en arrière-plan'), findsNothing);

    progress.message = 'Vérification auprès de la DGI...';
    await tester.pump();
    expect(find.text('Vérification auprès de la DGI...'), findsOneWidget);

    progress.close();
    await tester.pump(_frame);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('« Continuer en arrière-plan » et le retour système', (
    tester,
  ) async {
    final (context, navigator) = await _pumpHome(tester);
    final progress = ScanProgress.show(context, 'Vérification...');
    var calls = 0;
    progress.onBackground = () => calls++;
    await tester.pump(_frame);

    await tester.tap(find.text('Continuer en arrière-plan'));
    expect(calls, 1);

    // Le retour système ne ferme pas le dialogue de lui-même…
    await navigator.maybePop();
    await tester.pump();
    expect(calls, 2);
    expect(find.byType(Dialog), findsOneWidget);

    progress.close();
    await tester.pump(_frame);
  });

  testWidgets('retire SA route, même si un écran a été empilé au-dessus', (
    tester,
  ) async {
    final (context, navigator) = await _pumpHome(tester);
    final progress = ScanProgress.show(context, 'Vérification...');
    await tester.pump(_frame);

    // Par exemple : session expirée, redirection vers la connexion.
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('connexion')),
      ),
    );
    await tester.pump(_frame);

    progress.close();
    progress.close(); // idempotent
    progress.message = 'ignoré après fermeture';
    await tester.pump(_frame);

    expect(find.text('connexion'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });
}
