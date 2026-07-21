/// Garde d'authentification globale.
///
/// Placée au-dessus du Navigator (via `MaterialApp.builder`), elle ramène
/// l'utilisateur à l'écran de connexion dès que la session est perdue, quel
/// que soit l'écran affiché — y compris ceux poussés directement par
/// `Navigator.push` sans passer par la table de routes.
///
/// Elle remplace les gardes qui étaient dupliquées dans chaque écran d'accueil
/// et que les autres écrans n'avaient pas.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/providers/auth_provider.dart';

class AuthGuard extends StatefulWidget {
  const AuthGuard({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> {
  AuthProvider? _auth;

  /// La redirection ne se déclenche que sur une transition
  /// *authentifié → non authentifié*, autrement dit une session PERDUE.
  ///
  /// Au démarrage, l'état passe par `unauthenticated` avant toute connexion :
  /// rediriger là aussi entrerait en conflit avec le SplashScreen, qui gère
  /// déjà l'aiguillage initial.
  bool _wasAuthenticated = false;

  /// Empêche d'empiler plusieurs redirections si plusieurs notifications
  /// arrivent avant que la frame suivante ne soit rendue.
  bool _redirecting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (identical(auth, _auth)) return;
    _auth?.removeListener(_onAuthChanged);
    _auth = auth..addListener(_onAuthChanged);
    _wasAuthenticated = auth.isAuthenticated;
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null) return;

    final isAuthenticated = auth.isAuthenticated;
    final sessionLost = _wasAuthenticated && !isAuthenticated;
    _wasAuthenticated = isAuthenticated;

    if (!sessionLost || _redirecting) return;
    _redirecting = true;

    // La notification peut survenir pendant une phase de build : différer la
    // navigation à la frame suivante.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _redirecting = false;
      widget.navigatorKey.currentState
          ?.pushNamedAndRemoveUntil('/login', (route) => false);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
