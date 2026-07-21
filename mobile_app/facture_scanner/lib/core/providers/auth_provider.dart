/// Authentication Provider
/// Manages user authentication state
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/database_service.dart';
import '../models/user.dart';

enum AuthState { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final DatabaseService _db = DatabaseService();
  
  AuthState _state = AuthState.initial;
  User? _user;
  String? _errorMessage;
  
  AuthState get state => _state;
  User? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _state == AuthState.authenticated;
  bool get isLoading => _state == AuthState.loading;
  
  AuthProvider() {
    // Brancher la déconnexion automatique sur expiration de token (401).
    ApiService.onUnauthorized = handleSessionExpired;
    _checkAuth();
  }
  
  Future<void> _checkAuth() async {
    _state = AuthState.loading;
    notifyListeners();
    
    await _api.init();

    if (_api.isAuthenticated) {
      _user = _api.currentUser;
      _state = AuthState.authenticated;
    } else {
      // Distinguer « jamais connecté » d'une session arrivée à expiration :
      // sans message, l'utilisateur retrouve l'écran de connexion sans
      // comprendre pourquoi.
      if (_api.sessionExpiredAtStartup) {
        _errorMessage = 'Votre session a expiré. Veuillez vous reconnecter.';
        // Les données locales du compte précédent n'ont plus lieu d'être.
        unawaited(_db.clearAllData().catchError((_) {}));
      }
      _state = AuthState.unauthenticated;
    }

    notifyListeners();
  }
  
  /// Identifiant pour lequel un code a été demandé, conservé entre les deux
  /// étapes de la connexion (l'écran le réaffiche et le renvoie à la vérif).
  String? _pendingLogin;
  String? get pendingLogin => _pendingLogin;

  /// True dès qu'un code a été demandé : l'écran bascule alors sur la saisie
  /// du code à 6 chiffres.
  bool get isAwaitingOtp => _pendingLogin != null;

  /// Étape 1 — demander l'envoi d'un code de connexion par email.
  Future<bool> requestOtp(String login) async {
    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _api.requestOtp(login);

      if (response.success) {
        _pendingLogin = login;
        _state = AuthState.unauthenticated;
        notifyListeners();
        return true;
      } else {
        _errorMessage = response.errorMessage ?? "Impossible d'envoyer le code";
        _state = AuthState.error;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Erreur: ${e.toString()}';
      _state = AuthState.error;
      notifyListeners();
      return false;
    }
  }

  /// Étape 2 — échanger le code reçu par email contre un token.
  Future<bool> verifyOtp(String otp) async {
    final login = _pendingLogin;
    if (login == null) {
      _errorMessage = "Demandez d'abord un code de connexion.";
      _state = AuthState.error;
      notifyListeners();
      return false;
    }

    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _api.verifyOtp(login, otp);

      if (response.success) {
        _user = _api.currentUser;
        _pendingLogin = null;
        _state = AuthState.authenticated;
        notifyListeners();
        return true;
      } else {
        _errorMessage = response.errorMessage ?? 'Code invalide ou expiré';
        _state = AuthState.error;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Erreur: ${e.toString()}';
      _state = AuthState.error;
      notifyListeners();
      return false;
    }
  }

  /// Revenir à la saisie de l'identifiant (bouton « Modifier l'identifiant »).
  void resetOtpFlow() {
    _pendingLogin = null;
    _errorMessage = null;
    if (_state == AuthState.error) {
      _state = AuthState.unauthenticated;
    }
    notifyListeners();
  }
  
  Future<void> logout() async {
    _state = AuthState.loading;
    notifyListeners();
    
    await _api.logout();
    await _db.clearAllData();
    
    _user = null;
    _pendingLogin = null;
    _state = AuthState.unauthenticated;
    notifyListeners();
  }

  /// Gérer l'expiration de session (appelé par d'autres providers)
  // Garde d'exclusion : plusieurs réponses 401 simultanées ne doivent
  // déclencher qu'UN SEUL traitement d'expiration (évite doubles dialogs
  // et déconnexions concurrentes).
  bool _handlingSessionExpiry = false;

  void handleSessionExpired() {
    if (_handlingSessionExpiry) return;
    if (_state == AuthState.unauthenticated && _user == null) return;
    _handlingSessionExpiry = true;

    _user = null;
    _pendingLogin = null;
    _errorMessage = 'Votre session a expiré. Veuillez vous reconnecter.';
    _state = AuthState.unauthenticated;
    notifyListeners();

    // Nettoyer les données locales de manière asynchrone (non bloquant),
    // puis libérer la garde une fois le nettoyage terminé.
    Future.wait([
      _api.logout().catchError((_) {}),
      _db.clearAllData().catchError((_) {}),
    ]).whenComplete(() {
      _handlingSessionExpiry = false;
    });
  }
  
  void clearError() {
    _errorMessage = null;
    if (_state == AuthState.error) {
      _state = AuthState.unauthenticated;
    }
    notifyListeners();
  }
  
  /// Update base URL (for server configuration)
  Future<void> setServerUrl(String url) async {
    await _api.setBaseUrl(url);
  }
  
  String get serverUrl => _api.baseUrl;
}
