/// Sync Service for Offline/Online Synchronization
/// Handles syncing pending scans when connectivity is restored
/// Supports both raw URL syncs and pre-parsed DGI data syncs

import 'dart:async';

import 'api_service.dart';
import 'database_service.dart';

class SyncService {
  final ApiService _api = ApiService();
  final DatabaseService _db = DatabaseService();
  
  bool _isSyncing = false;
  
  // Singleton
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();
  
  bool get isSyncing => _isSyncing;
  
  /// Sync all pending scans to server (both parsed and unparsed)
  Future<SyncResult> syncPendingScans() async {
    if (_isSyncing) {
      return SyncResult(
        success: false,
        message: 'Synchronisation déjà en cours',
      );
    }
    
    _isSyncing = true;
    
    try {
      // Check if we have connectivity
      final isOnline = await _api.healthCheck();
      if (!isOnline) {
        _isSyncing = false;
        return SyncResult(
          success: false,
          message: 'Pas de connexion au serveur',
        );
      }
      
      int totalSynced = 0;
      int totalDuplicates = 0;
      int totalErrors = 0;
      
      // 1. Sync parsed scans (with DGI data) via enriched endpoint
      final parsedResult = await _syncParsedScans();
      totalSynced += parsedResult.syncedCount;
      totalDuplicates += parsedResult.duplicateCount;
      totalErrors += parsedResult.errorCount;
      
      // 2. Sync unparsed scans (URL only) via standard endpoint
      final unparsedResult = await _syncUnparsedScans();
      totalSynced += unparsedResult.syncedCount;
      totalDuplicates += unparsedResult.duplicateCount;
      totalErrors += unparsedResult.errorCount;
      
      // Cleanup synced scans
      await _db.deleteSyncedScans();
      
      _isSyncing = false;
      
      if (totalSynced + totalDuplicates + totalErrors == 0) {
        return SyncResult(
          success: true,
          message: 'Aucun scan à synchroniser',
          syncedCount: 0,
        );
      }
      
      return SyncResult(
        success: true,
        message: 'Synchronisation terminée',
        syncedCount: totalSynced,
        duplicateCount: totalDuplicates,
        errorCount: totalErrors,
      );
      
    } catch (e) {
      _isSyncing = false;
      return SyncResult(
        success: false,
        message: 'Erreur: ${e.toString()}',
      );
    }
  }
  
  /// Sync scans with pre-parsed DGI data
  Future<SyncResult> _syncParsedScans() async {
    final parsedScans = await _db.getParsedPendingScans();
    if (parsedScans.isEmpty) {
      return SyncResult(success: true, message: '', syncedCount: 0);
    }
    
    // Prepare enriched scans for sync
    final scansToSync = parsedScans.map((scan) => {
      'qr_url': scan['qr_url'],
      'scanned_at': scan['scanned_at'],
      'parsed_data': {
        'supplier_name': scan['supplier_name'],
        'supplier_code_dgi': scan['supplier_code_dgi'],
        'customer_name': scan['customer_name'],
        'customer_code_dgi': scan['customer_code_dgi'],
        'invoice_number_dgi': scan['invoice_number_dgi'],
        'invoice_date': scan['invoice_date'],
        'verification_id': scan['verification_id'],
        'amount_ttc': scan['amount_ttc'],
      },
    }).toList();
    
    // Try the pre-parsed endpoint first
    final response = await _api.syncParsedScans(scansToSync);
    
    if (response.success && response.data != null) {
      final results = response.data!['results'] as List? ?? [];
      final summary = response.data!['summary'] as Map<String, dynamic>? ?? {};
      
      // Mark scans based on results
      for (int i = 0; i < results.length && i < parsedScans.length; i++) {
        final result = results[i] as Map<String, dynamic>;
        final pendingScan = parsedScans[i];
        
        if (result['success'] == true || result['error_code'] == 'DUPLICATE') {
          await _db.markScanSynced(pendingScan['id'] as int);
        } else {
          await _db.markScanFailed(
            pendingScan['id'] as int,
            result['error']?.toString() ?? 'Erreur inconnue',
          );
        }
      }
      
      return SyncResult(
        success: true,
        message: '',
        syncedCount: (summary['successful'] as int?) ?? 0,
        duplicateCount: (summary['duplicates'] as int?) ?? 0,
        errorCount: (summary['errors'] as int?) ?? 0,
      );
    }
    
    return SyncResult(
      success: false,
      message: response.errorMessage ?? 'Erreur sync parsed',
    );
  }
  
  /// Sync scans with URL only (standard flow - server does DGI fetch)
  Future<SyncResult> _syncUnparsedScans() async {
    final pendingScans = await _db.getUnparsedPendingScans();
    if (pendingScans.isEmpty) {
      return SyncResult(success: true, message: '', syncedCount: 0);
    }
    
    // Prepare scans for sync
    final scansToSync = pendingScans.map((scan) => {
      'qr_url': scan['qr_url'],
      'scanned_at': scan['scanned_at'],
    }).toList();
    
    // Send to server
    final response = await _api.syncOfflineScans(scansToSync);
    
    if (response.success && response.data != null) {
      final results = response.data!['results'] as List? ?? [];
      final summary = response.data!['summary'] as Map<String, dynamic>? ?? {};
      
      // Mark scans based on results
      for (int i = 0; i < results.length && i < pendingScans.length; i++) {
        final result = results[i] as Map<String, dynamic>;
        final pendingScan = pendingScans[i];
        
        if (result['success'] == true || result['error_code'] == 'DUPLICATE') {
          await _db.markScanSynced(pendingScan['id'] as int);
        } else {
          await _db.markScanFailed(
            pendingScan['id'] as int,
            result['error']?.toString() ?? 'Erreur inconnue',
          );
        }
      }
      
      return SyncResult(
        success: true,
        message: '',
        syncedCount: (summary['successful'] as int?) ?? 0,
        duplicateCount: (summary['duplicates'] as int?) ?? 0,
        errorCount: (summary['errors'] as int?) ?? 0,
      );
    }
    
    return SyncResult(
      success: false,
      message: response.errorMessage ?? 'Erreur sync',
    );
  }
  
  /// Get number of pending scans
  Future<int> getPendingCount() async {
    return await _db.getPendingScansCount();
  }
}

class SyncResult {
  final bool success;
  final String message;
  final int syncedCount;
  final int duplicateCount;
  final int errorCount;
  
  SyncResult({
    required this.success,
    required this.message,
    this.syncedCount = 0,
    this.duplicateCount = 0,
    this.errorCount = 0,
  });
  
  int get totalProcessed => syncedCount + duplicateCount + errorCount;
}
