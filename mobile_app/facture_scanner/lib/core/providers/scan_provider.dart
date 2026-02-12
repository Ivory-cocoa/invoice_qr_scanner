/// Scan Provider
/// Manages QR code scanning and invoice creation

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../models/scan_record.dart';
import 'auth_provider.dart';

enum ScanState { idle, scanning, processing, success, error, duplicate }

class ScanProvider extends ChangeNotifier {
  final ApiService _api = ApiService();
  final DatabaseService _db = DatabaseService();
  final SyncService _sync = SyncService();
  
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
  
  // Getters
  ScanState get state => _state;
  String? get message => _message;
  ScanRecord? get lastScanResult => _lastScanResult;
  List<ScanRecord> get history => _history;
  bool get isLoadingHistory => _isLoadingHistory;
  int get pendingScansCount => _pendingScansCount;
  Map<String, dynamic>? get stats => _stats;
  bool get hasPendingScans => _pendingScansCount > 0;
  
  // Stats avec compteurs locaux combinés
  // Retourne toujours les stats (même si vides) pour permettre l'affichage des compteurs locaux
  Map<String, dynamic> get combinedStats {
    final baseStats = _stats ?? {
      'total_scans': 0,
      'successful_scans': 0,
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
  Future<void> processQrCode(String qrContent, {bool isOnline = true}) async {
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
    
    if (isOnline) {
      // Online mode: send to server immediately
      await _processOnline(qrContent);
    } else {
      // Offline mode: save locally
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
  
  Future<void> _processOnline(String qrUrl) async {
    try {
      final response = await _api.scanQrCode(qrUrl);
      
      if (response.success && response.data != null) {
        _state = ScanState.success;
        _message = response.data!['message'] ?? 'Facture créée avec succès';
        _localSuccessCount++; // Incrémenter le compteur de succès
        
        // Create a ScanRecord from response if available
        if (response.data!.containsKey('record')) {
          final recordData = response.data!['record'];
          final invoiceData = response.data!['invoice'];
          
          _lastScanResult = ScanRecord(
            id: recordData['id'],
            reference: recordData['reference'] ?? '',
            qrUuid: extractUuidFromUrl(qrUrl) ?? '',
            supplierName: invoiceData?['partner_name'] ?? '',
            supplierCodeDgi: '',
            invoiceNumberDgi: invoiceData?['ref'] ?? '',
            invoiceDate: null,
            amountTtc: (invoiceData?['amount_total'] as num?)?.toDouble() ?? 0,
            currency: 'XOF',
            state: 'done',
            stateLabel: 'Facture créée',
            invoiceId: invoiceData?['id'],
            invoiceName: invoiceData?['name'],
            invoiceState: invoiceData?['state'],
            scanDate: DateTime.now(),
            scannedBy: _auth?.user?.name ?? '',
          );
        }
        
        // Refresh history
        await loadHistory();
      } else if (response.errorCode == 'DUPLICATE') {
        _state = ScanState.duplicate;
        _message = response.errorMessage ?? 'Cette facture a déjà été scannée';
        _localDuplicateCount++; // Incrémenter le compteur de doublons
        
        // Get existing record info
        if (response.data != null && response.data!.containsKey('existing_record')) {
          final existing = response.data!['existing_record'];
          _lastScanResult = ScanRecord(
            id: existing['id'] ?? 0,
            reference: existing['reference'] ?? '',
            qrUuid: extractUuidFromUrl(qrUrl) ?? '',
            supplierName: existing['supplier_name'] ?? '',
            supplierCodeDgi: existing['supplier_code_dgi'] ?? '',
            invoiceNumberDgi: existing['invoice_number_dgi'] ?? '',
            amountTtc: (existing['amount_ttc'] as num?)?.toDouble() ?? 0,
            currency: 'XOF',
            state: 'done',
            stateLabel: 'Doublon',
            invoiceId: existing['invoice_id'],
            invoiceName: existing['invoice_name'],
            scanDate: existing['scan_date'] != null
                ? DateTime.tryParse(existing['scan_date'])
                : null,
            scannedBy: existing['scanned_by'] ?? '',
            duplicateCount: existing['duplicate_count'] ?? 1,
            lastDuplicateAttempt: existing['last_duplicate_attempt'] != null
                ? DateTime.tryParse(existing['last_duplicate_attempt'])
                : DateTime.now(),
          );
        }
      } else {
        // Vérifier si c'est une erreur d'authentification
        if (response.errorCode == 'AUTH_INVALID' || 
            response.errorCode == 'AUTH_REQUIRED' ||
            response.errorCode == 'TOKEN_EXPIRED') {
          _state = ScanState.error;
          _message = 'Session expirée. Veuillez vous reconnecter.';
          // Notifier que l'authentification a expiré
          _auth?.handleSessionExpired();
        } else {
          _state = ScanState.error;
          _message = response.errorMessage ?? 'Erreur lors du scan';
          _localErrorCount++; // Incrémenter le compteur d'erreurs
        }
      }
    } catch (e) {
      _state = ScanState.error;
      _message = 'Erreur: ${e.toString()}';
      _localErrorCount++; // Incrémenter le compteur d'erreurs
    }
    
    notifyListeners();
  }
  
  Future<void> _processOffline(String qrUrl, String qrUuid) async {
    try {
      await _db.addPendingScan(qrUrl, qrUuid);
      await _updatePendingCount();
      
      _state = ScanState.success;
      _message = 'Scan enregistré localement. Sera synchronisé une fois en ligne.';
    } catch (e) {
      _state = ScanState.error;
      _message = 'Erreur lors de l\'enregistrement local';
    }
    
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
}
