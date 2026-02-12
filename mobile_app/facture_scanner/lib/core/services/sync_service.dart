/// Sync Service for Offline/Online Synchronization
/// Handles syncing pending scans when connectivity is restored

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
  
  /// Sync all pending scans to server
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
      
      // Get pending scans
      final pendingScans = await _db.getPendingScans();
      if (pendingScans.isEmpty) {
        _isSyncing = false;
        return SyncResult(
          success: true,
          message: 'Aucun scan à synchroniser',
          syncedCount: 0,
        );
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
        
        // Cleanup synced scans
        await _db.deleteSyncedScans();
        
        _isSyncing = false;
        return SyncResult(
          success: true,
          message: 'Synchronisation terminée',
          syncedCount: (summary['successful'] as int?) ?? 0,
          duplicateCount: (summary['duplicates'] as int?) ?? 0,
          errorCount: (summary['errors'] as int?) ?? 0,
        );
      }
      
      _isSyncing = false;
      return SyncResult(
        success: false,
        message: response.errorMessage ?? 'Erreur de synchronisation',
      );
      
    } catch (e) {
      _isSyncing = false;
      return SyncResult(
        success: false,
        message: 'Erreur: ${e.toString()}',
      );
    }
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
