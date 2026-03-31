/// Scan Provider
/// Manages QR code scanning and invoice creation

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../services/dgi_extractor_service.dart';
import '../services/dgi_parser_service.dart';
import '../models/scan_record.dart';
import 'auth_provider.dart';

enum ScanState { idle, scanning, processing, success, error, duplicate, alreadyProcessed, manualEntry }

class ScanProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final DatabaseService _db = DatabaseService();
  final SyncService _sync = SyncService();
  final DgiExtractorService _extractor = DgiExtractorService();
  
  AuthProvider? _auth;
  
  ScanState _state = ScanState.idle;
  String? _message;
  ScanRecord? _lastScanResult;
  List<ScanRecord> _history = [];
  bool _isLoadingHistory = false;
  int _pendingScansCount = 0;
  Map<String, dynamic>? _stats;
  
  // Compteurs locaux pour les KPIs (quand offline ou en temps réel)
  int _localDuplicateCount = 0;
  int _localErrorCount = 0;
  int _localSuccessCount = 0;
  
  // Progression de l'extraction DGI
  String? _extractionProgress;
  
  // Timeout configurable pour la vérification DGI (en secondes)
  static const String _timeoutKey = 'dgi_verification_timeout';
  static const int defaultTimeout = 5;
  int _verificationTimeout = defaultTimeout;
  
  // Données DGI extraites (pour le formulaire manuel)
  DgiParsedData? _extractedDgiData;
  String? _pendingQrUrl;
  double _lastVerificationDuration = 0;
  
  // Getters
  ScanState get state => _state;
  String? get message => _message;
  ScanRecord? get lastScanResult => _lastScanResult;
  List<ScanRecord> get history => _history;
  bool get isLoadingHistory => _isLoadingHistory;
  int get pendingScansCount => _pendingScansCount;
  Map<String, dynamic>? get stats => _stats;
  bool get hasPendingScans => _pendingScansCount > 0;
  String? get extractionProgress => _extractionProgress;
  int get verificationTimeout => _verificationTimeout;
  DgiParsedData? get extractedDgiData => _extractedDgiData;
  String? get pendingQrUrl => _pendingQrUrl;
  double get lastVerificationDuration => _lastVerificationDuration;
  
  // Stats avec compteurs locaux combinés
  // Retourne toujours les stats (même si vides) pour permettre l'affichage des compteurs locaux
  Map<String, dynamic> get combinedStats {
    final baseStats = _stats ?? {
      'total_scans': 0,
      'successful_scans': 0,
      'processed_scans': 0,
      'unprocessed_scans': 0,
      'duplicate_attempts': 0,
      'records_with_duplicates': 0,
      'error_scans': 0,
      'total_amount': 0,
    };
    return {
      ...baseStats,
      'duplicate_attempts': (baseStats['duplicate_attempts'] ?? 0) + _localDuplicateCount,
      'error_scans': (baseStats['error_scans'] ?? 0) + _localErrorCount,
      'successful_scans': (baseStats['successful_scans'] ?? 0) + _localSuccessCount,
      'total_scans': (baseStats['total_scans'] ?? 0) + _localDuplicateCount + _localErrorCount + _localSuccessCount,
    };
  }
  
  void updateAuth(AuthProvider auth) {
    _auth = auth;
  }
  
  /// Extract UUID from DGI URL
  String? extractUuidFromUrl(String url) {
    final pattern = RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', caseSensitive: false);
    final match = pattern.firstMatch(url);
    return match?.group(0)?.toLowerCase();
  }
  
  /// Validate QR code URL
  bool isValidDgiUrl(String url) {
    return url.contains('services.fne.dgi.gouv.ci');
  }
  
  /// Process a scanned QR code
  /// If [localExtraction] is true, extract DGI data locally and save for scheduled sync
  Future<void> processQrCode(String qrContent, {bool isOnline = true, bool localExtraction = false}) async {
    _state = ScanState.processing;
    _message = null;
    _lastScanResult = null;
    notifyListeners();
    
    // Validate URL
    if (!isValidDgiUrl(qrContent)) {
      _state = ScanState.error;
      _message = 'QR-code non valide. Seules les factures DGI sont supportées.';
      _localErrorCount++; // Incrémenter le compteur d'erreurs
      notifyListeners();
      return;
    }
    
    final qrUuid = extractUuidFromUrl(qrContent);
    if (qrUuid == null) {
      _state = ScanState.error;
      _message = 'Impossible d\'extraire l\'identifiant du QR-code';
      _localErrorCount++; // Incrémenter le compteur d'erreurs
      notifyListeners();
      return;
    }
    
    // Check local cache first (for duplicates) - but we'll still report to server
    final cached = await _db.findInHistoryCache(qrUuid);
    if (cached != null) {
      _state = ScanState.duplicate;
      _message = 'Cette facture a déjà été scannée';
      _lastScanResult = cached;
      _localDuplicateCount++; // Incrémenter le compteur de doublons local
      
      // IMPORTANT: Signaler le doublon au serveur pour incrémenter le compteur
      if (isOnline) {
        _reportDuplicateToServer(qrContent);
      }
      
      notifyListeners();
      return;
    }
    
    // Check pending scans
    final isPending = await _db.isPendingScan(qrUuid);
    if (isPending) {
      _state = ScanState.duplicate;
      _message = 'Ce scan est en attente de synchronisation';
      _localDuplicateCount++; // Incrémenter le compteur de doublons local
      notifyListeners();
      return;
    }
    
    if (isOnline && !localExtraction) {
      // Online mode uses processQrCodeWithExtraction() instead
      _state = ScanState.error;
      _message = 'Veuillez utiliser le scan en ligne avec extraction.';
      notifyListeners();
    } else {
      // Offline or local extraction mode: extract locally and save
      await _processOffline(qrContent, qrUuid);
    }
  }
  
  /// Report a duplicate detection to the server (fire and forget)
  Future<void> _reportDuplicateToServer(String qrUrl) async {
    try {
      final response = await _api.reportDuplicate(qrUrl);
      if (response.success && response.data != null) {
        // Mettre à jour le cache local avec les nouvelles données du serveur
        if (response.data!.containsKey('record')) {
          final recordData = response.data!['record'];
          final updatedRecord = ScanRecord(
            id: recordData['id'] ?? 0,
            reference: recordData['reference'] ?? '',
            qrUuid: extractUuidFromUrl(qrUrl) ?? '',
            supplierName: recordData['supplier_name'] ?? '',
            supplierCodeDgi: recordData['supplier_code_dgi'] ?? '',
            invoiceNumberDgi: recordData['invoice_number_dgi'] ?? '',
            amountTtc: (recordData['amount_ttc'] as num?)?.toDouble() ?? 0,
            currency: 'XOF',
            state: recordData['state'] ?? 'done',
            stateLabel: recordData['state_label'] ?? 'Doublon',
            invoiceId: recordData['invoice_id'],
            invoiceName: recordData['invoice_name'],
            scanDate: recordData['scan_date'] != null
                ? DateTime.tryParse(recordData['scan_date'])
                : null,
            scannedBy: recordData['scanned_by'] ?? '',
            duplicateCount: recordData['duplicate_count'] ?? 1,
            lastDuplicateAttempt: recordData['last_duplicate_attempt'] != null
                ? DateTime.tryParse(recordData['last_duplicate_attempt'])
                : DateTime.now(),
            lastDuplicateUser: recordData['last_duplicate_user'],
          );
          
          // Mettre à jour le cache local
          await _db.cacheScanHistory([updatedRecord]);
          _lastScanResult = updatedRecord;
          notifyListeners();
        }
      }
    } catch (e) {
      // Ignorer les erreurs - le doublon a déjà été signalé localement
    }
  }

  /// Process QR code with client-side DGI extraction and configurable timeout.
  /// If extraction takes longer than the timeout, switches to manual entry.
  /// Returns true if manual entry is needed (caller should navigate to form).
  Future<bool> processQrCodeWithExtraction(String qrContent, {bool isOnline = true}) async {
    _state = ScanState.processing;
    _message = null;
    _lastScanResult = null;
    _extractedDgiData = null;
    _pendingQrUrl = null;
    _lastVerificationDuration = 0;
    notifyListeners();

    // Validate URL
    if (!isValidDgiUrl(qrContent)) {
      _state = ScanState.error;
      _message = 'QR-code non valide. Seules les factures DGI sont supportées.';
      _localErrorCount++;
      notifyListeners();
      return false;
    }

    final qrUuid = extractUuidFromUrl(qrContent);
    if (qrUuid == null) {
      _state = ScanState.error;
      _message = 'Impossible d\'extraire l\'identifiant du QR-code';
      _localErrorCount++;
      notifyListeners();
      return false;
    }

    // Check local cache for duplicates
    final cached = await _db.findInHistoryCache(qrUuid);
    if (cached != null) {
      _state = ScanState.duplicate;
      _message = 'Cette facture a déjà été scannée';
      _lastScanResult = cached;
      _localDuplicateCount++;
      if (isOnline) _reportDuplicateToServer(qrContent);
      notifyListeners();
      return false;
    }

    // Check pending scans
    final isPending = await _db.isPendingScan(qrUuid);
    if (isPending) {
      _state = ScanState.duplicate;
      _message = 'Ce scan est en attente de synchronisation';
      _localDuplicateCount++;
      notifyListeners();
      return false;
    }

    if (!isOnline) {
      await _processOffline(qrContent, qrUuid);
      return false;
    }

    // Online: check server for duplicates first
    try {
      final checkResponse = await _api.checkQrCode(qrContent);
      if (!checkResponse.success && checkResponse.errorCode == 'DUPLICATE') {
        _state = ScanState.duplicate;
        _message = checkResponse.errorMessage ?? 'Cette facture a déjà été scannée';
        _localDuplicateCount++;
        if (checkResponse.data != null && checkResponse.data!.containsKey('existing_record')) {
          final existing = checkResponse.data!['existing_record'];
          _lastScanResult = ScanRecord.fromJson(existing);
        }
        notifyListeners();
        return false;
      }
    } catch (_) {
      // If check fails, continue with extraction
    }

    // Start client-side DGI extraction with timeout
    _extractionProgress = 'Vérification DGI en cours...';
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    DgiExtractionResult? extractionResult;
    bool timedOut = false;

    try {
      extractionResult = await _extractor.extractFromUrl(
        qrContent,
        onProgress: (msg) {
          _extractionProgress = msg;
          notifyListeners();
        },
      ).timeout(
        Duration(seconds: _verificationTimeout),
        onTimeout: () {
          timedOut = true;
          return DgiExtractionResult(
            success: false,
            error: 'Timeout: vérification DGI dépassée',
          );
        },
      );
    } catch (e) {
      timedOut = true;
      extractionResult = DgiExtractionResult(
        success: false,
        error: 'Erreur extraction: ${e.toString()}',
      );
    }

    stopwatch.stop();
    _lastVerificationDuration = stopwatch.elapsedMilliseconds / 1000.0;
    _extractionProgress = null;

    if (extractionResult != null && extractionResult.success && extractionResult.data != null && !timedOut) {
      // Extraction succeeded within timeout - send to server automatically
      return await _submitExtractedData(qrContent, extractionResult.data!, _lastVerificationDuration, false);
    }

    // Timeout or extraction failed - switch to manual entry
    _extractedDgiData = extractionResult?.data;
    _pendingQrUrl = qrContent;
    _state = ScanState.manualEntry;
    _message = timedOut
        ? 'Vérification DGI trop lente (${_lastVerificationDuration.toStringAsFixed(1)}s). Saisie manuelle requise.'
        : 'Site DGI indisponible. Saisie manuelle requise.';
    notifyListeners();
    return true; // Caller should navigate to ManualEntryScreen
  }

  /// Validate QR code and check for duplicates (without starting extraction).
  /// Returns ({bool valid, String? error, String? qrUuid, bool isDuplicate, ScanRecord? existing}).
  /// Used by HomeScreen before enqueuing to BackgroundScanQueue.
  Future<({bool valid, String? error, String? qrUuid, bool isDuplicate, ScanRecord? existing})>
      validateQrForQueue(String qrContent, {bool checkServer = true}) async {
    // Validate URL
    if (!isValidDgiUrl(qrContent)) {
      _localErrorCount++;
      notifyListeners();
      return (valid: false, error: 'QR-code non valide. Seules les factures DGI sont supportées.', qrUuid: null, isDuplicate: false, existing: null);
    }

    final qrUuid = extractUuidFromUrl(qrContent);
    if (qrUuid == null) {
      _localErrorCount++;
      notifyListeners();
      return (valid: false, error: 'Impossible d\'extraire l\'identifiant du QR-code', qrUuid: null, isDuplicate: false, existing: null);
    }

    // Check local cache
    final cached = await _db.findInHistoryCache(qrUuid);
    if (cached != null) {
      _localDuplicateCount++;
      if (checkServer) _reportDuplicateToServer(qrContent);
      notifyListeners();
      return (valid: false, error: 'Cette facture a déjà été scannée', qrUuid: qrUuid, isDuplicate: true, existing: cached);
    }

    // Check pending scans
    final isPending = await _db.isPendingScan(qrUuid);
    if (isPending) {
      _localDuplicateCount++;
      notifyListeners();
      return (valid: false, error: 'Ce scan est en attente de synchronisation', qrUuid: qrUuid, isDuplicate: true, existing: null);
    }

    // Check server
    if (checkServer) {
      try {
        final checkResponse = await _api.checkQrCode(qrContent);
        if (!checkResponse.success && checkResponse.errorCode == 'DUPLICATE') {
          _localDuplicateCount++;
          ScanRecord? existing;
          if (checkResponse.data != null && checkResponse.data!.containsKey('existing_record')) {
            existing = ScanRecord.fromJson(checkResponse.data!['existing_record']);
          }
          notifyListeners();
          return (valid: false, error: checkResponse.errorMessage ?? 'Cette facture a déjà été scannée', qrUuid: qrUuid, isDuplicate: true, existing: existing);
        }
      } catch (_) {
        // If check fails, allow enqueue
      }
    }

    return (valid: true, error: null, qrUuid: qrUuid, isDuplicate: false, existing: null);
  }

  /// Submit data from the manual entry form to the server
  Future<void> submitManualEntry({
    required String qrUrl,
    required String supplierName,
    String? supplierCodeDgi,
    String? customerName,
    String? customerCodeDgi,
    required String invoiceNumberDgi,
    String? invoiceDate,
    required double amountTtc,
    required double verificationDuration,
  }) async {
    _state = ScanState.processing;
    _message = 'Création de la facture...';
    notifyListeners();

    try {
      final response = await _api.scanWithData(
        qrUrl: qrUrl,
        supplierName: supplierName,
        supplierCodeDgi: supplierCodeDgi,
        customerName: customerName,
        customerCodeDgi: customerCodeDgi,
        invoiceNumberDgi: invoiceNumberDgi,
        invoiceDate: invoiceDate,
        amountTtc: amountTtc,
        verificationDuration: verificationDuration,
        isManualEntry: true,
      );

      if (response.success && response.data != null) {
        _state = ScanState.success;
        _message = response.data!['message'] ?? 'Facture créée avec succès (saisie manuelle)';
        _localSuccessCount++;

        if (response.data!.containsKey('record')) {
          _lastScanResult = ScanRecord.fromJson(response.data!['record']);
        }
        await loadHistory();
      } else if (response.errorCode == 'DUPLICATE') {
        _state = ScanState.duplicate;
        _message = response.errorMessage ?? 'Cette facture a déjà été scannée';
        _localDuplicateCount++;
        if (response.data != null && response.data!.containsKey('existing_record')) {
          _lastScanResult = ScanRecord.fromJson(response.data!['existing_record']);
        }
      } else {
        _state = ScanState.error;
        _message = _getUserFriendlyMessage(response.errorCode, response.errorMessage);
        _localErrorCount++;
      }
    } catch (e) {
      _state = ScanState.error;
      _message = _getUserFriendlyMessage(null, e.toString());
      _localErrorCount++;
    }

    _extractedDgiData = null;
    _pendingQrUrl = null;
    notifyListeners();
  }

  /// Submit automatically extracted data to the server (non-manual)
  Future<bool> _submitExtractedData(String qrUrl, DgiParsedData data, double duration, bool isManual) async {
    try {
      final response = await _api.scanWithData(
        qrUrl: qrUrl,
        supplierName: data.supplierName,
        supplierCodeDgi: data.supplierCodeDgi,
        customerName: data.customerName,
        customerCodeDgi: data.customerCodeDgi,
        invoiceNumberDgi: data.invoiceNumberDgi,
        invoiceDate: data.invoiceDate,
        amountTtc: data.amountTtc,
        verificationDuration: duration,
        isManualEntry: isManual,
      );

      if (response.success && response.data != null) {
        _state = ScanState.success;
        _message = response.data!['message'] ?? 'Facture créée avec succès';
        _localSuccessCount++;

        if (response.data!.containsKey('record')) {
          _lastScanResult = ScanRecord.fromJson(response.data!['record']);
        }
        await loadHistory();
      } else if (response.errorCode == 'DUPLICATE') {
        _state = ScanState.duplicate;
        _message = response.errorMessage ?? 'Cette facture a déjà été scannée';
        _localDuplicateCount++;
        if (response.data != null && response.data!.containsKey('existing_record')) {
          _lastScanResult = ScanRecord.fromJson(response.data!['existing_record']);
        }
      } else {
        _state = ScanState.error;
        _message = _getUserFriendlyMessage(response.errorCode, response.errorMessage);
        _localErrorCount++;
      }
      notifyListeners();
      return false; // No manual entry needed
    } catch (e) {
      _state = ScanState.error;
      _message = _getUserFriendlyMessage(null, e.toString());
      _localErrorCount++;
      notifyListeners();
      return false;
    }
  }

  /// Get the configurable verification timeout (in seconds)
  Future<void> loadVerificationTimeout() async {
    final prefs = await SharedPreferences.getInstance();
    _verificationTimeout = prefs.getInt(_timeoutKey) ?? defaultTimeout;
    notifyListeners();
  }

  /// Set the verification timeout (in seconds)
  Future<void> setVerificationTimeout(int seconds) async {
    if (seconds < 1) seconds = 1;
    if (seconds > 60) seconds = 60;
    _verificationTimeout = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_timeoutKey, seconds);
    notifyListeners();
  }

  /// Convertit les codes d'erreur en messages clairs pour l'utilisateur
  String _getUserFriendlyMessage(String? errorCode, String? rawMessage) {
    switch (errorCode) {
      case 'DGI_INCOMPLETE':
        return 'Le site DGI n\'a pas fourni toutes les informations de la facture. '
               'Veuillez réessayer dans quelques instants.';
      case 'DGI_ERROR':
        return 'Impossible d\'accéder au site DGI pour vérifier cette facture. '
               'Le site peut être temporairement indisponible.';
      case 'INVOICE_ERROR':
        return 'La facture n\'a pas pu être créée dans le système. '
               'Veuillez contacter l\'administrateur si le problème persiste.';
      case 'INVALID_URL':
        return 'Le QR code scanné n\'est pas un QR code de facture DGI valide. '
               'Veuillez vérifier que vous scannez le bon QR code.';
      case 'SERVER_BUSY':
        return 'Le serveur traite d\'autres scans en ce moment. '
               'Veuillez patienter quelques secondes et réessayer.';
      case 'TIMEOUT':
        return 'Le traitement prend plus de temps que prévu. '
               'Le site DGI peut être lent. Veuillez réessayer.';
      case 'NETWORK_ERROR':
        return 'Pas de connexion internet. '
               'Vérifiez votre Wi-Fi ou vos données mobiles.';
      case 'AUTH_INVALID':
      case 'AUTH_REQUIRED':
      case 'TOKEN_EXPIRED':
        return 'Votre session a expiré. Veuillez vous reconnecter.';
      default:
        // Si le message brut contient des infos utiles du serveur, l'utiliser
        if (rawMessage != null && rawMessage.isNotEmpty) {
          // Nettoyer les messages techniques
          if (rawMessage.contains('TimeoutException') || rawMessage.contains('timeout')) {
            return 'Le traitement a pris trop de temps. Veuillez réessayer.';
          }
          if (rawMessage.contains('SocketException') || rawMessage.contains('Connection refused')) {
            return 'Impossible de contacter le serveur. Vérifiez votre connexion.';
          }
          // Retourner le message tel quel s'il vient du serveur (déjà en français)
          return rawMessage;
        }
        return 'Une erreur est survenue lors du scan. Veuillez réessayer.';
    }
  }
  
  Future<void> _processOffline(String qrUrl, String qrUuid) async {
    try {
      // Tenter d'extraire les données DGI localement via WebView
      _extractionProgress = 'Chargement de la page DGI...';
      notifyListeners();
      
      final extractionResult = await _extractor.extractFromUrl(
        qrUrl,
        onProgress: (msg) {
          _extractionProgress = msg;
          notifyListeners();
        },
      );
      
      _extractionProgress = null;
      
      if (extractionResult.success && extractionResult.data != null) {
        // Sauvegarder avec les données parsées
        await _db.addParsedPendingScan(qrUrl, qrUuid, extractionResult.data!);
        await _updatePendingCount();
        
        _state = ScanState.success;
        _message = 'Facture analysée et enregistrée localement.\n'
            'Fournisseur: ${extractionResult.data!.supplierName}\n'
            'Montant: ${extractionResult.data!.formattedAmount}\n'
            'Sera synchronisée à l\'heure programmée.';
        _localSuccessCount++;
      } else {
        // Fallback: sauvegarder juste l'URL (extraction échouée)
        await _db.addPendingScan(qrUrl, qrUuid);
        await _updatePendingCount();
        
        _state = ScanState.success;
        _message = 'Scan enregistré localement (données non extraites).\n'
            'Veuillez rescanner cette facture pour extraire les données.';
      }
    } catch (e) {
      // Fallback en cas d'erreur: sauvegarder juste l'URL
      try {
        await _db.addPendingScan(qrUrl, qrUuid);
        await _updatePendingCount();
        _state = ScanState.success;
        _message = 'Scan enregistré localement.\nVeuillez rescanner pour extraire les données.';
      } catch (e2) {
        _state = ScanState.error;
        _message = 'Erreur lors de l\'enregistrement local';
      }
    }
    
    _extractionProgress = null;
    notifyListeners();
  }
  
  /// Load scan history from server or cache
  Future<void> loadHistory({bool forceRefresh = false, bool isOnline = true}) async {
    _isLoadingHistory = true;
    notifyListeners();
    
    try {
      if (isOnline) {
        final response = await _api.getHistory();
        
        if (response.success && response.data != null) {
          final records = (response.data!['records'] as List)
              .map((json) => ScanRecord.fromJson(json))
              .toList();
          
          _history = records;
          
          // Cache the history
          await _db.cacheScanHistory(records);
        }
      } else {
        // Load from cache
        _history = await _db.getCachedHistory();
      }
    } catch (e) {
      // On error, try loading from cache
      _history = await _db.getCachedHistory();
    }
    
    _isLoadingHistory = false;
    notifyListeners();
  }
  
  /// Load statistics
  Future<void> loadStats() async {
    try {
      final response = await _api.getStats();
      if (response.success && response.data != null) {
        _stats = response.data;
        // Réinitialiser les compteurs locaux quand on récupère les stats du serveur
        _localDuplicateCount = 0;
        _localErrorCount = 0;
        _localSuccessCount = 0;
        notifyListeners();
      }
    } catch (e) {
      // Ignore stats errors
    }
  }
  
  /// Sync pending scans
  Future<SyncResult> syncPendingScans() async {
    final result = await _sync.syncPendingScans();
    await _updatePendingCount();
    
    if (result.success && result.syncedCount > 0) {
      await loadHistory();
      await loadStats(); // Recharger les stats après sync
    }
    
    notifyListeners();
    return result;
  }
  
  Future<void> _updatePendingCount() async {
    _pendingScansCount = await _db.getPendingScansCount();
    notifyListeners();
  }
  
  /// Initialize provider
  Future<void> init() async {
    await _updatePendingCount();
    await loadVerificationTimeout();
    // Nettoyer les données de plus de 24h au démarrage
    await _db.cleanupOldData();
  }
  
  /// Reset state
  void resetState() {
    _state = ScanState.idle;
    _message = null;
    _lastScanResult = null;
    notifyListeners();
  }
  
  /// Clear offline data only (keep history from server)
  Future<void> clearOfflineData() async {
    await _db.clearAllData();
    _pendingScansCount = 0;
    _localDuplicateCount = 0;
    _localErrorCount = 0;
    _localSuccessCount = 0;
    notifyListeners();
  }
  
  /// Clear all data (on logout)
  Future<void> clearData() async {
    _history = [];
    _stats = null;
    _pendingScansCount = 0;
    _lastScanResult = null;
    _state = ScanState.idle;
    _localDuplicateCount = 0;
    _localErrorCount = 0;
    _localSuccessCount = 0;
    _extractionProgress = null;
    notifyListeners();
  }

  /// Mark a scan record as processed (traité)
  Future<bool> markAsProcessed(int recordId) async {
    try {
      final response = await _api.markProcessed(recordId);
      if (response.success && response.data != null) {
        // Update the record in local history
        final recordData = response.data!['record'];
        if (recordData != null) {
          final updatedRecord = ScanRecord.fromJson(recordData);
          _updateRecordInHistory(updatedRecord);
        }
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Mark a scan record as unprocessed (non traité)
  Future<bool> markAsUnprocessed(int recordId) async {
    try {
      final response = await _api.markUnprocessed(recordId);
      if (response.success && response.data != null) {
        // Update the record in local history
        final recordData = response.data!['record'];
        if (recordData != null) {
          final updatedRecord = ScanRecord.fromJson(recordData);
          _updateRecordInHistory(updatedRecord);
        }
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Bulk mark scan records as processed (traités en masse)
  Future<Map<String, dynamic>?> bulkMarkAsProcessed({List<int>? recordIds, int maxRecords = 50}) async {
    try {
      final response = await _api.bulkMarkProcessed(
        recordIds: recordIds,
        maxRecords: maxRecords,
      );
      if (response.success && response.data != null) {
        // Refresh history after bulk operation
        await loadHistory();
        await loadStats();
        return response.data!['summary'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Update a single record in the local history list
  void _updateRecordInHistory(ScanRecord updatedRecord) {
    final index = _history.indexWhere((r) => r.id == updatedRecord.id);
    if (index != -1) {
      _history[index] = updatedRecord;
    }
  }

  // ============ Traiteur-specific methods ============
  
  /// Traiteur stats
  Map<String, dynamic>? _traiteurStats;
  Map<String, dynamic>? get traiteurStats => _traiteurStats;
  
  /// Pending invoices for Traiteur
  List<ScanRecord> _pendingInvoices = [];
  List<ScanRecord> get pendingInvoices => _pendingInvoices;
  bool _isLoadingPending = false;
  bool get isLoadingPending => _isLoadingPending;

  /// Process QR code as Traiteur (find existing invoice → mark as processed)
  Future<void> processQrCodeAsTraiteur(String qrContent) async {
    _state = ScanState.processing;
    _message = null;
    _lastScanResult = null;
    notifyListeners();

    // Validate URL
    if (!isValidDgiUrl(qrContent)) {
      _state = ScanState.error;
      _message = 'QR-code non valide. Seules les factures DGI sont supportées.';
      notifyListeners();
      return;
    }

    try {
      final response = await _api.scanToProcess(qrContent);
      
      if (response.success && response.data != null) {
        _state = ScanState.success;
        _message = response.data!['message'] ?? 'Facture traitée avec succès';
        
        if (response.data!.containsKey('record')) {
          final recordData = response.data!['record'];
          _lastScanResult = ScanRecord.fromJson(recordData);
        }
        
        // Refresh data
        await loadTraiteurPending();
        await loadTraiteurStats();
      } else {
        if (response.errorCode == 'AUTH_INVALID' || 
            response.errorCode == 'AUTH_REQUIRED' ||
            response.errorCode == 'TOKEN_EXPIRED') {
          _state = ScanState.error;
          _message = 'Session expirée. Veuillez vous reconnecter.';
          _auth?.handleSessionExpired();
        } else if (response.errorCode == 'ALREADY_PROCESSED') {
          _state = ScanState.alreadyProcessed;
          _message = response.errorMessage ?? 'Cette facture a déjà été traitée';
          if (response.data != null && response.data!.containsKey('record')) {
            _lastScanResult = ScanRecord.fromJson(response.data!['record']);
          }
        } else {
          _state = ScanState.error;
          _message = response.errorMessage ?? 'Erreur lors du traitement';
        }
      }
    } catch (e) {
      _state = ScanState.error;
      _message = 'Erreur: ${e.toString()}';
    }
    
    notifyListeners();
  }

  /// Load pending invoices for Traiteur
  Future<void> loadTraiteurPending({int page = 1, int limit = 20}) async {
    _isLoadingPending = true;
    notifyListeners();
    
    try {
      final response = await _api.getTraiteurPending(page: page, limit: limit);
      if (response.success && response.data != null) {
        _pendingInvoices = (response.data!['records'] as List)
            .map((json) => ScanRecord.fromJson(json))
            .toList();
      }
    } catch (e) {
      // Keep existing data on error
    }
    
    _isLoadingPending = false;
    notifyListeners();
  }

  /// Load Traiteur statistics
  Future<void> loadTraiteurStats() async {
    try {
      final response = await _api.getTraiteurStats();
      if (response.success && response.data != null) {
        _traiteurStats = response.data;
        notifyListeners();
      }
    } catch (e) {
      // Ignore stats errors
    }
  }
}
