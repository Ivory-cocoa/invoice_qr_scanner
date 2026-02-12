/// Enhanced API Service with Retry Logic and Better Error Handling
/// Service API robuste avec gestion avancée des erreurs et retry automatique

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/environment.dart';
import '../models/api_response.dart';
import '../models/user.dart';
import '../models/scan_record.dart';

/// Configuration des retries
class RetryConfig {
  final int maxAttempts;
  final Duration initialDelay;
  final double backoffMultiplier;
  final Duration maxDelay;
  final List<String> retryableErrorCodes;

  const RetryConfig({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(seconds: 30),
    this.retryableErrorCodes = const ['NETWORK_ERROR', 'TIMEOUT', 'HTTP_503', 'HTTP_502', 'HTTP_504'],
  });
}

/// Types d'erreurs API
enum ApiErrorType {
  network,
  timeout,
  authentication,
  authorization,
  validation,
  notFound,
  serverError,
  unknown,
}

/// Exception API personnalisée
class ApiException implements Exception {
  final String code;
  final String message;
  final ApiErrorType type;
  final dynamic originalError;
  final int? statusCode;

  ApiException({
    required this.code,
    required this.message,
    required this.type,
    this.originalError,
    this.statusCode,
  });

  @override
  String toString() => 'ApiException[$code]: $message';

  bool get isRetryable => [
    ApiErrorType.network,
    ApiErrorType.timeout,
    ApiErrorType.serverError,
  ].contains(type);
}

/// Classe principale du service API amélioré
class EnhancedApiService {
  static const String _baseUrlKey = 'api_base_url';
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'current_user';
  static const String _tokenExpiryKey = 'token_expiry';

  static String get _defaultBaseUrl => AppConfig.apiBaseUrl;

  String? _baseUrl;
  String? _token;
  User? _currentUser;
  DateTime? _tokenExpiry;
  
  final RetryConfig _retryConfig;
  final Duration _defaultTimeout;
  final http.Client _httpClient;

  // Callbacks pour les événements
  VoidCallback? onTokenExpired;
  VoidCallback? onUnauthorized;
  Function(ApiException)? onError;

  // Request queue pour limiter les requêtes concurrentes
  final _requestQueue = <Future>[];
  static const int _maxConcurrentRequests = 5;

  // Singleton
  static EnhancedApiService? _instance;
  
  factory EnhancedApiService({
    RetryConfig retryConfig = const RetryConfig(),
    Duration defaultTimeout = const Duration(seconds: 30),
    http.Client? httpClient,
  }) {
    _instance ??= EnhancedApiService._internal(
      retryConfig: retryConfig,
      defaultTimeout: defaultTimeout,
      httpClient: httpClient ?? http.Client(),
    );
    return _instance!;
  }

  EnhancedApiService._internal({
    required RetryConfig retryConfig,
    required Duration defaultTimeout,
    required http.Client httpClient,
  }) : _retryConfig = retryConfig,
       _defaultTimeout = defaultTimeout,
       _httpClient = httpClient;

  // Getters
  String get baseUrl => _baseUrl ?? _defaultBaseUrl;
  String? get token => _token;
  User? get currentUser => _currentUser;
  bool get isAuthenticated => _token != null && _currentUser != null && !isTokenExpired;
  bool get isTokenExpired => _tokenExpiry != null && DateTime.now().isAfter(_tokenExpiry!);

  /// Initialise le service
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_baseUrlKey) ?? _defaultBaseUrl;
    _token = prefs.getString(_tokenKey);
    
    final expiryMs = prefs.getInt(_tokenExpiryKey);
    if (expiryMs != null) {
      _tokenExpiry = DateTime.fromMillisecondsSinceEpoch(expiryMs);
    }

    final userJson = prefs.getString(_userKey);
    if (userJson != null) {
      try {
        _currentUser = User.fromJson(jsonDecode(userJson));
      } catch (e) {
        debugPrint('Erreur parsing user: $e');
        await _clearAuthData();
      }
    }

    // Vérifier si le token est expiré
    if (isTokenExpired) {
      await _clearAuthData();
    }
  }

  /// Configure l'URL de base
  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, _baseUrl!);
  }

  /// Login avec gestion des erreurs améliorée
  Future<ApiResponse<Map<String, dynamic>>> login(String login, String password) async {
    try {
      final response = await _executeRequest<Map<String, dynamic>>(
        method: 'POST',
        endpoint: '/api/v1/invoice-scanner/auth/login',
        body: {'login': login, 'password': password},
        authenticated: false,
        retryEnabled: false, // Pas de retry pour le login
      );

      if (response.success && response.data != null) {
        await _handleLoginSuccess(response.data!);
      }

      return response;
    } catch (e) {
      return _handleException<Map<String, dynamic>>(e);
    }
  }

  Future<void> _handleLoginSuccess(Map<String, dynamic> data) async {
    _token = data['token'];
    _currentUser = User.fromJson(data['user']);
    
    // Calculer l'expiration du token (par défaut 8 heures)
    final expiresIn = data['expires_in'] as int? ?? 28800;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, _token!);
    await prefs.setString(_userKey, jsonEncode(_currentUser!.toJson()));
    await prefs.setInt(_tokenExpiryKey, _tokenExpiry!.millisecondsSinceEpoch);
  }

  /// Logout propre
  Future<void> logout() async {
    try {
      await _executeRequest<void>(
        method: 'POST',
        endpoint: '/api/v1/invoice-scanner/auth/logout',
        body: {},
        retryEnabled: false,
      );
    } catch (_) {
      // Ignorer les erreurs de logout
    } finally {
      await _clearAuthData();
    }
  }

  Future<void> _clearAuthData() async {
    _token = null;
    _currentUser = null;
    _tokenExpiry = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_tokenExpiryKey);
  }

  /// Scan QR code avec retry automatique
  Future<ApiResponse<Map<String, dynamic>>> scanQrCode(String qrUrl) async {
    return _executeRequest<Map<String, dynamic>>(
      method: 'POST',
      endpoint: '/api/v1/invoice-scanner/scan',
      body: {'qr_url': qrUrl},
    );
  }

  /// Vérification QR code
  Future<ApiResponse<Map<String, dynamic>>> checkQrCode(String qrUrl) async {
    return _executeRequest<Map<String, dynamic>>(
      method: 'POST',
      endpoint: '/api/v1/invoice-scanner/check',
      body: {'qr_url': qrUrl},
    );
  }

  /// Historique avec pagination
  Future<ApiResponse<Map<String, dynamic>>> getHistory({
    int page = 1,
    int limit = 20,
    String? state,
    String? sortBy,
    bool sortDesc = true,
  }) async {
    return _executeRequest<Map<String, dynamic>>(
      method: 'POST',
      endpoint: '/api/v1/invoice-scanner/history',
      body: {
        'page': page,
        'limit': limit,
        if (state != null) 'state': state,
        if (sortBy != null) 'sort_by': sortBy,
        'sort_desc': sortDesc,
      },
    );
  }

  /// Détails facture
  Future<ApiResponse<Map<String, dynamic>>> getInvoiceDetails(int invoiceId) async {
    return _executeRequest<Map<String, dynamic>>(
      method: 'POST',
      endpoint: '/api/v1/invoice-scanner/invoice/$invoiceId',
      body: {},
    );
  }

  /// Statistiques
  Future<ApiResponse<Map<String, dynamic>>> getStats({
    String? period,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    return _executeRequest<Map<String, dynamic>>(
      method: 'POST',
      endpoint: '/api/v1/invoice-scanner/stats',
      body: {
        if (period != null) 'period': period,
        if (dateFrom != null) 'date_from': dateFrom.toIso8601String().split('T')[0],
        if (dateTo != null) 'date_to': dateTo.toIso8601String().split('T')[0],
      },
    );
  }

  /// Synchronisation batch des scans offline
  Future<ApiResponse<Map<String, dynamic>>> syncOfflineScans(
    List<Map<String, dynamic>> scans, {
    bool continueOnError = true,
  }) async {
    return _executeRequest<Map<String, dynamic>>(
      method: 'POST',
      endpoint: '/api/v1/invoice-scanner/sync',
      body: {
        'scans': scans,
        'continue_on_error': continueOnError,
      },
      timeout: Duration(seconds: 60), // Timeout plus long pour la sync
    );
  }

  /// Health check avec timeout court
  Future<bool> healthCheck() async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/invoice-scanner/health');
      final response = await _httpClient.get(uri).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Ping pour vérifier la connectivité
  Future<Duration?> ping() async {
    try {
      final stopwatch = Stopwatch()..start();
      final healthy = await healthCheck();
      stopwatch.stop();
      return healthy ? stopwatch.elapsed : null;
    } catch (_) {
      return null;
    }
  }

  /// Exécute une requête avec retry et gestion d'erreurs
  Future<ApiResponse<T>> _executeRequest<T>({
    required String method,
    required String endpoint,
    Map<String, dynamic>? body,
    bool authenticated = true,
    bool retryEnabled = true,
    Duration? timeout,
  }) async {
    // Vérifier l'authentification si nécessaire
    if (authenticated && !isAuthenticated) {
      if (isTokenExpired) {
        onTokenExpired?.call();
        return ApiResponse<T>(
          success: false,
          errorCode: 'TOKEN_EXPIRED',
          errorMessage: 'Votre session a expiré. Veuillez vous reconnecter.',
        );
      }
      onUnauthorized?.call();
      return ApiResponse<T>(
        success: false,
        errorCode: 'NOT_AUTHENTICATED',
        errorMessage: 'Authentification requise',
      );
    }

    // Attendre si trop de requêtes en cours
    await _waitForSlot();

    int attempt = 0;
    Duration delay = _retryConfig.initialDelay;
    ApiException? lastException;

    while (attempt < (retryEnabled ? _retryConfig.maxAttempts : 1)) {
      attempt++;
      
      try {
        final response = await _doRequest<T>(
          method: method,
          endpoint: endpoint,
          body: body,
          authenticated: authenticated,
          timeout: timeout ?? _defaultTimeout,
        );

        // Succès ou erreur non-retryable
        return response;
        
      } on ApiException catch (e) {
        lastException = e;
        
        // Gérer l'expiration du token
        if (e.statusCode == 401) {
          await _clearAuthData();
          onTokenExpired?.call();
          return ApiResponse<T>(
            success: false,
            errorCode: 'TOKEN_EXPIRED',
            errorMessage: 'Session expirée',
          );
        }

        // Ne pas retry si l'erreur n'est pas retryable
        if (!e.isRetryable || !retryEnabled) {
          onError?.call(e);
          return ApiResponse<T>(
            success: false,
            errorCode: e.code,
            errorMessage: e.message,
          );
        }

        // Attendre avant le retry
        if (attempt < _retryConfig.maxAttempts) {
          debugPrint('Retry $attempt/${_retryConfig.maxAttempts} après ${delay.inSeconds}s...');
          await Future.delayed(delay);
          delay = Duration(
            milliseconds: (delay.inMilliseconds * _retryConfig.backoffMultiplier).toInt(),
          );
          if (delay > _retryConfig.maxDelay) {
            delay = _retryConfig.maxDelay;
          }
        }
      }
    }

    // Toutes les tentatives ont échoué
    onError?.call(lastException!);
    return ApiResponse<T>(
      success: false,
      errorCode: lastException?.code ?? 'MAX_RETRIES',
      errorMessage: lastException?.message ?? 'Échec après plusieurs tentatives',
    );
  }

  Future<void> _waitForSlot() async {
    while (_requestQueue.length >= _maxConcurrentRequests) {
      await Future.any(_requestQueue);
    }
  }

  Future<ApiResponse<T>> _doRequest<T>({
    required String method,
    required String endpoint,
    Map<String, dynamic>? body,
    required bool authenticated,
    required Duration timeout,
  }) async {
    final completer = Completer<void>();
    _requestQueue.add(completer.future);

    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Client-Version': '1.0.0',
        'X-Client-Platform': Platform.operatingSystem,
        if (authenticated && _token != null) 'Authorization': 'Bearer $_token',
      };

      http.Response response;
      
      switch (method.toUpperCase()) {
        case 'POST':
          response = await _httpClient.post(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          ).timeout(timeout);
          break;
        case 'GET':
          response = await _httpClient.get(uri, headers: headers).timeout(timeout);
          break;
        case 'PUT':
          response = await _httpClient.put(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          ).timeout(timeout);
          break;
        case 'DELETE':
          response = await _httpClient.delete(uri, headers: headers).timeout(timeout);
          break;
        default:
          throw ApiException(
            code: 'INVALID_METHOD',
            message: 'Méthode HTTP non supportée: $method',
            type: ApiErrorType.unknown,
          );
      }

      return _parseResponse<T>(response);
      
    } on SocketException catch (e) {
      throw ApiException(
        code: 'NETWORK_ERROR',
        message: 'Pas de connexion internet',
        type: ApiErrorType.network,
        originalError: e,
      );
    } on TimeoutException catch (e) {
      throw ApiException(
        code: 'TIMEOUT',
        message: 'Le serveur ne répond pas',
        type: ApiErrorType.timeout,
        originalError: e,
      );
    } on FormatException catch (e) {
      throw ApiException(
        code: 'PARSE_ERROR',
        message: 'Erreur de format de réponse',
        type: ApiErrorType.unknown,
        originalError: e,
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        code: 'UNKNOWN_ERROR',
        message: 'Erreur inattendue: ${e.toString()}',
        type: ApiErrorType.unknown,
        originalError: e,
      );
    } finally {
      completer.complete();
      _requestQueue.remove(completer.future);
    }
  }

  ApiResponse<T> _parseResponse<T>(http.Response response) {
    // Gérer les codes HTTP d'erreur
    if (response.statusCode >= 400) {
      final errorType = _getErrorType(response.statusCode);
      final errorMessage = _getHttpErrorMessage(response.statusCode);
      
      throw ApiException(
        code: 'HTTP_${response.statusCode}',
        message: errorMessage,
        type: errorType,
        statusCode: response.statusCode,
      );
    }

    // Parser la réponse JSON
    try {
      final jsonResponse = jsonDecode(response.body);

      if (jsonResponse['success'] == true) {
        return ApiResponse<T>(
          success: true,
          data: jsonResponse['data'] as T?,
          message: jsonResponse['message'],
        );
      } else {
        final error = jsonResponse['error'];
        return ApiResponse<T>(
          success: false,
          errorCode: error?['code'] ?? 'UNKNOWN_ERROR',
          errorMessage: error?['message'] ?? 'Une erreur est survenue',
          data: jsonResponse['data'] as T?,
        );
      }
    } catch (e) {
      throw ApiException(
        code: 'PARSE_ERROR',
        message: 'Impossible de parser la réponse du serveur',
        type: ApiErrorType.unknown,
        originalError: e,
      );
    }
  }

  ApiErrorType _getErrorType(int statusCode) {
    switch (statusCode) {
      case 401:
        return ApiErrorType.authentication;
      case 403:
        return ApiErrorType.authorization;
      case 404:
        return ApiErrorType.notFound;
      case 422:
        return ApiErrorType.validation;
      case >= 500:
        return ApiErrorType.serverError;
      default:
        return ApiErrorType.unknown;
    }
  }

  String _getHttpErrorMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Requête invalide';
      case 401:
        return 'Session expirée, veuillez vous reconnecter';
      case 403:
        return 'Accès non autorisé';
      case 404:
        return 'Ressource non trouvée';
      case 422:
        return 'Données invalides';
      case 429:
        return 'Trop de requêtes, veuillez patienter';
      case 500:
        return 'Erreur serveur interne';
      case 502:
        return 'Serveur temporairement indisponible';
      case 503:
        return 'Service en maintenance';
      case 504:
        return 'Délai d\'attente serveur dépassé';
      default:
        return 'Erreur HTTP $statusCode';
    }
  }

  ApiResponse<T> _handleException<T>(Object e) {
    if (e is ApiException) {
      return ApiResponse<T>(
        success: false,
        errorCode: e.code,
        errorMessage: e.message,
      );
    }
    return ApiResponse<T>(
      success: false,
      errorCode: 'UNKNOWN_ERROR',
      errorMessage: 'Erreur: ${e.toString()}',
    );
  }

  /// Dispose du service
  void dispose() {
    _httpClient.close();
    _instance = null;
  }
}

/// Extension pour faciliter l'utilisation
extension ApiResponseExtension<T> on ApiResponse<T> {
  /// Vérifie si l'erreur est récupérable
  bool get isRecoverable => [
    'NETWORK_ERROR',
    'TIMEOUT',
    'HTTP_502',
    'HTTP_503',
    'HTTP_504',
  ].contains(errorCode);

  /// Message utilisateur friendly
  String get userMessage {
    if (success) return message ?? 'Opération réussie';
    return errorMessage ?? 'Une erreur est survenue';
  }
}
