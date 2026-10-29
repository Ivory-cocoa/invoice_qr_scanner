/// Scan Progress Dialog - Design Professionnel ICP
/// Dialogue bloquant affiché entre la fermeture du scanner et le résultat
library;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Pilote un dialogue de progression : l'ouvre, met à jour son message, le
/// referme.
///
/// La route est retirée par référence ([NavigatorState.removeRoute]) plutôt
/// que par un `pop()` aveugle : si un autre écran s'est empilé entre-temps
/// (session expirée, par exemple), c'est bien CE dialogue qui disparaît, et
/// non l'écran du dessus.
class ScanProgress {
  final NavigatorState _navigator;
  final ValueNotifier<String> _message;
  final ValueNotifier<VoidCallback?> _onBackground =
      ValueNotifier<VoidCallback?>(null);
  late final DialogRoute<void> _route;

  ScanProgress._(this._navigator, String message)
      : _message = ValueNotifier<String>(message);

  /// Ouvre le dialogue sur le Navigator racine de [context].
  factory ScanProgress.show(BuildContext context, String message) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final progress = ScanProgress._(navigator, message);
    progress._route = DialogRoute<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (_) => _ScanProgressDialog(
        message: progress._message,
        onBackground: progress._onBackground,
      ),
    );
    navigator.push(progress._route);
    return progress;
  }

  set message(String value) {
    if (!_closed) _message.value = value;
  }

  /// Affiche le bouton « Continuer en arrière-plan » (et l'associe au retour
  /// système) ; `null` le masque.
  set onBackground(VoidCallback? callback) {
    if (!_closed) _onBackground.value = callback;
  }

  bool _closed = false;

  /// Referme le dialogue. Sans effet s'il l'est déjà.
  void close() {
    if (_closed) return;
    _closed = true;
    // Les ValueNotifier ne sont pas `dispose()` : ils ne tiennent aucune
    // ressource, et le dialogue peut encore les écouter le temps d'être
    // démonté. Ils disparaissent avec cet objet.
    if (_route.isActive) _navigator.removeRoute(_route);
  }
}

class _ScanProgressDialog extends StatelessWidget {
  final ValueNotifier<String> message;
  final ValueNotifier<VoidCallback?> onBackground;

  const _ScanProgressDialog({
    required this.message,
    required this.onBackground,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VoidCallback?>(
      valueListenable: onBackground,
      builder: (context, background, _) {
        return PopScope(
          // Le retour système ne ferme pas le dialogue « dans le vide » : il
          // équivaut à « Continuer en arrière-plan » quand c'est possible.
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) background?.call();
          },
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: AppTheme.getPrimary(context),
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<String>(
                    valueListenable: message,
                    builder: (context, text, _) => Text(
                      text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.getTextSecondary(context),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (background != null)
                    TextButton(
                      onPressed: background,
                      child: const Text('Continuer en arrière-plan'),
                    )
                  else
                    const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
