/// Connectivity Provider
/// Monitors network connectivity status

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityProvider extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _subscription;
  
  bool _isOnline = true;
  bool _isChecking = false;
  
  bool get isOnline => _isOnline;
  bool get isChecking => _isChecking;
  
  ConnectivityProvider() {
    _init();
  }
  
  Future<void> _init() async {
    // Check initial status
    await checkConnectivity();
    
    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      _updateConnectivity(result);
    });
  }
  
  Future<void> checkConnectivity() async {
    _isChecking = true;
    notifyListeners();
    
    try {
      final result = await _connectivity.checkConnectivity();
      _updateConnectivity(result);
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }
  
  void _updateConnectivity(ConnectivityResult result) {
    final wasOnline = _isOnline;
    _isOnline = result != ConnectivityResult.none;
    
    if (wasOnline != _isOnline) {
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
