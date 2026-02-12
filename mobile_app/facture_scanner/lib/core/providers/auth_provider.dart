/// Authentication Provider
/// Manages user authentication state

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
      _state = AuthState.unauthenticated;
    }
    
    notifyListeners();
  }
  
  Future<bool> login(String login, String password) async {
    _state = AuthState.loading;
    _errorMessage = null;
    notifyListeners();
    
    try {
      final response = await _api.login(login, password);
      
      if (response.success) {
        _user = _api.currentUser;
        _state = AuthState.authenticated;
        notifyListeners();
        return true;
      } else {
        _errorMessage = response.errorMessage ?? 'Erreur de connexion';
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
  
  Future<void> logout() async {
    _state = AuthState.loading;
    notifyListeners();
    
    await _api.logout();
    await _db.clearAllData();
    
    _user = null;
    _state = AuthState.unauthenticated;
    notifyListeners();
  }
  
  /// Gérer l'expiration de session (appelé par d'autres providers)
  void handleSessionExpired() {
    _user = null;
    _errorMessage = 'Votre session a expiré. Veuillez vous reconnecter.';
    _state = AuthState.unauthenticated;
    
    // Nettoyer les données locales de manière asynchrone
    _api.logout();
    _db.clearAllData();
    
    notifyListeners();
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
