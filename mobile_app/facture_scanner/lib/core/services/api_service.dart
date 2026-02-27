/// API Service for Facture Scanner
/// Handles all HTTP communications with Odoo backend

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/environment.dart';
import '../models/api_response.dart';
import '../models/user.dart';
import '../models/scan_record.dart';

class ApiService {
  static const String _baseUrlKey = 'api_base_url';
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'current_user';
  
  // Default URL from environment configuration
  static String get _defaultBaseUrl => AppConfig.apiBaseUrl;
  
  String? _baseUrl;
  String? _token;
  User? _currentUser;
  
  // Singleton
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();
  
  // Getters
  String get baseUrl => _baseUrl ?? _defaultBaseUrl;
  String? get token => _token;
  User? get currentUser => _currentUser;
  bool get isAuthenticated => _token != null && _currentUser != null;
  
  /// Initialize the API service
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_baseUrlKey) ?? _defaultBaseUrl;
    _token = prefs.getString(_tokenKey);
    
    final userJson = prefs.getString(_userKey);
    if (userJson != null) {
      try {
        _currentUser = User.fromJson(jsonDecode(userJson));
      } catch (e) {
        // Invalid user data, clear it
        await prefs.remove(_userKey);
      }
    }
  }
  
  /// Set API base URL
  Future<void> setBaseUrl(String url) async {
    // Ensure URL doesn't end with /
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, _baseUrl!);
  }
  
  /// Login with credentials
  Future<ApiResponse<Map<String, dynamic>>> login(String login, String password) async {
    final response = await _post<Map<String, dynamic>>('/api/v1/invoice-scanner/auth/login', {
      'login': login,
      'password': password,
    }, authenticated: false);
    
    if (response.success && response.data != null) {
      _token = response.data!['token'];
      _currentUser = User.fromJson(response.data!['user']);
      
      // Save to storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, _token!);
      await prefs.setString(_userKey, jsonEncode(_currentUser!.toJson()));
    }
    
    return response;
  }
  
  /// Logout
  Future<void> logout() async {
    // Try to logout on server (ignore errors)
    try {
      await _post<Map<String, dynamic>>('/api/v1/invoice-scanner/auth/logout', {});
    } catch (_) {}
    
    _token = null;
    _currentUser = null;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }
  
  /// Scan QR code and create invoice
  Future<ApiResponse<Map<String, dynamic>>> scanQrCode(String qrUrl) async {
    return await _post<Map<String, dynamic>>('/api/v1/invoice-scanner/scan', {
      'qr_url': qrUrl,
    });
  }
  
  /// Check if QR code already exists
  Future<ApiResponse<Map<String, dynamic>>> checkQrCode(String qrUrl) async {
    return await _post<Map<String, dynamic>>('/api/v1/invoice-scanner/check', {
      'qr_url': qrUrl,
    });
  }
  
  /// Get scan history
  Future<ApiResponse<Map<String, dynamic>>> getHistory({
    int page = 1,
    int limit = 20,
    String? state,
  }) async {
    return await _post<Map<String, dynamic>>('/api/v1/invoice-scanner/history', {
      'page': page,
      'limit': limit,
      if (state != null) 'state': state,
    });
  }
  
  /// Get invoice details
  Future<ApiResponse<Map<String, dynamic>>> getInvoiceDetails(int invoiceId) async {
    return await _post<Map<String, dynamic>>('/api/v1/invoice-scanner/invoice/$invoiceId', {});
  }
  
  /// Get statistics
  Future<ApiResponse<Map<String, dynamic>>> getStats() async {
    return await _post<Map<String, dynamic>>('/api/v1/invoice-scanner/stats', {});
  }
  
  /// Sync offline scans
  Future<ApiResponse<Map<String, dynamic>>> syncOfflineScans(List<Map<String, dynamic>> scans) async {
    return await _post<Map<String, dynamic>>('/api/v1/invoice-scanner/sync', {
      'scans': scans,
    });
  }
  
  /// Get errors list with filters
  Future<ApiResponse<Map<String, dynamic>>> getErrors({
    int page = 1,
    int limit = 20,
    String? dateFrom,
    String? dateTo,
    bool? retryPossible,
  }) async {
    return await _post<Map<String, dynamic>>('/api/v1/invoice-scanner/errors', {
      'page': page,
      'limit': limit,
      if (dateFrom != null) 'date_from': dateFrom,
      if (dateTo != null) 'date_to': dateTo,
      if (retryPossible != null) 'retry_possible': retryPossible,
    });
  }
  
  /// Retry a single error
  Future<ApiResponse<Map<String, dynamic>>> retryError(int recordId) async {
    return await _post<Map<String, dynamic>>('/api/v1/invoice-scanner/errors/$recordId/retry', {});
  }
  
  /// Bulk retry multiple errors
  Future<ApiResponse<Map<String, dynamic>>> bulkRetryErrors({
    List<int>? recordIds,
    int maxRecords = 50,
  }) async {
    return await _post<Map<String, dynamic>>('/api/v1/invoice-scanner/errors/bulk-retry', {
      if (recordIds != null) 'record_ids': recordIds,
      'max_records': maxRecords,
    });
  }
  
  /// Report a duplicate attempt to the server
  /// This ensures the server's duplicate_count is always incremented
  Future<ApiResponse<Map<String, dynamic>>> reportDuplicate(String qrUrl) async {
    return await _post<Map<String, dynamic>>('/api/v1/invoice-scanner/report-duplicate', {
      'qr_url': qrUrl,
    });
  }

  /// Mark a scan record as processed (traité)
  Future<ApiResponse<Map<String, dynamic>>> markProcessed(int recordId) async {
    return await _post<Map<String, dynamic>>('/api/v1/invoice-scanner/mark-processed/$recordId', {});
  }

  /// Mark a scan record as unprocessed (non traité)
  Future<ApiResponse<Map<String, dynamic>>> markUnprocessed(int recordId) async {
    return await _post<Map<String, dynamic>>('/api/v1/invoice-scanner/mark-unprocessed/$recordId', {});
  }

  /// Bulk mark scan records as processed (traités en masse)
  Future<ApiResponse<Map<String, dynamic>>> bulkMarkProcessed({
    List<int>? recordIds,
    int maxRecords = 50,
  }) async {
    return await _post<Map<String, dynamic>>('/api/v1/invoice-scanner/bulk-mark-processed', {
      if (recordIds != null) 'record_ids': recordIds,
      'max_records': maxRecords,
    });
  }

  // ============ Traiteur-specific endpoints ============

  /// Scan QR to find and process an existing invoice (Traiteur flow)
  Future<ApiResponse<Map<String, dynamic>>> scanToProcess(String qrUrl) async {
    return await _post<Map<String, dynamic>>('/api/v1/invoice-scanner/scan-to-process', {
      'qr_url': qrUrl,
    });
  }

  /// Get pending invoices for Traiteur
  Future<ApiResponse<Map<String, dynamic>>> getTraiteurPending({
    int page = 1,
    int limit = 20,
  }) async {
    return await _post<Map<String, dynamic>>('/api/v1/invoice-scanner/traiteur/pending', {
      'page': page,
      'limit': limit,
    });
  }

  /// Get Traiteur statistics
  Future<ApiResponse<Map<String, dynamic>>> getTraiteurStats() async {
    return await _post<Map<String, dynamic>>('/api/v1/invoice-scanner/traiteur/stats', {});
  }

  /// Health check
  Future<bool> healthCheck() async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/invoice-scanner/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
  
  /// Generic POST request
  Future<ApiResponse<T>> _post<T>(
    String endpoint,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (authenticated && _token != null) 'Authorization': 'Bearer $_token',
      };
      
      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));
      
      // Vérifier que la réponse est bien du JSON avant de parser
      final contentType = response.headers['content-type'] ?? '';
      final body_text = response.body.trimLeft();
      
      if (!contentType.contains('application/json') && body_text.startsWith('<')) {
        // Le serveur a renvoyé du HTML (page d'erreur, redirection, etc.)
        String errorMsg;
        if (response.statusCode == 301 || response.statusCode == 302) {
          errorMsg = 'Le serveur a redirigé la requête. Vérifiez l\'URL du serveur.';
        } else if (response.statusCode >= 500) {
          errorMsg = 'Erreur interne du serveur (${response.statusCode}). Réessayez plus tard.';
        } else if (response.statusCode == 404) {
          errorMsg = 'Endpoint non trouvé. Vérifiez la version de l\'API sur le serveur.';
        } else {
          errorMsg = 'Le serveur a renvoyé une réponse inattendue (${response.statusCode}). Vérifiez l\'URL du serveur.';
        }
        return ApiResponse<T>(
          success: false,
          errorCode: 'SERVER_ERROR',
          errorMessage: errorMsg,
        );
      }
      
      // Parse la réponse JSON pour tous les status (200, 400, etc.)
      final jsonResponse = jsonDecode(response.body);
      
      if (response.statusCode == 200 && jsonResponse['success'] == true) {
        return ApiResponse<T>(
          success: true,
          data: jsonResponse['data'] as T?,
          message: jsonResponse['message'],
        );
      } else {
        // Erreur - extraire le code et message d'erreur
        final error = jsonResponse['error'];
        return ApiResponse<T>(
          success: false,
          errorCode: error?['code'] ?? 'UNKNOWN_ERROR',
          errorMessage: error?['message'] ?? 'Une erreur est survenue',
          data: jsonResponse['data'] as T?, // Inclure les données (ex: existing_record pour les doublons)
        );
      }
    } on SocketException {
      return ApiResponse<T>(
        success: false,
        errorCode: 'NETWORK_ERROR',
        errorMessage: 'Pas de connexion internet',
      );
    } on TimeoutException {
      return ApiResponse<T>(
        success: false,
        errorCode: 'TIMEOUT',
        errorMessage: 'Le serveur ne répond pas',
      );
    } on FormatException {
      return ApiResponse<T>(
        success: false,
        errorCode: 'PARSE_ERROR',
        errorMessage: 'Réponse invalide du serveur. Vérifiez l\'URL et la connexion.',
      );
    } catch (e) {
      return ApiResponse<T>(
        success: false,
        errorCode: 'UNKNOWN_ERROR',
        errorMessage: 'Erreur: ${e.toString()}',
      );
    }
  }
}
