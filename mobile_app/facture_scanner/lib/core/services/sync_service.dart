/// Sync Service for Offline/Online Synchronization
/// Handles syncing pending scans when connectivity is restored
/// Supports both raw URL syncs and pre-parsed DGI data syncs

import 'dart:async';

import 'api_service.dart';
import 'database_service.dart';
import 'dgi_extractor_service.dart';
import 'dgi_parser_service.dart';

class SyncService {
  final ApiService _api = ApiService();
  final DatabaseService _db = DatabaseService();
  final DgiExtractorService _extractor = DgiExtractorService();
  
  bool _isSyncing = false;
  
  /// Optional callback for sync progress updates
  void Function(String message)? onProgress;
  
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
      onProgress?.call('Synchronisation des scans pré-analysés...');
      final parsedResult = await _syncParsedScans();
      totalSynced += parsedResult.syncedCount;
      totalDuplicates += parsedResult.duplicateCount;
      totalErrors += parsedResult.errorCount;
      
      // 2. For unparsed scans: extract DGI data first, then sync as parsed
      onProgress?.call('Extraction des données DGI pour les scans en attente...');
      final unparsedResult = await _extractAndSyncUnparsedScans();
      totalSynced += unparsedResult.syncedCount;
      totalDuplicates += unparsedResult.duplicateCount;
      totalErrors += unparsedResult.errorCount;
      
      // Cleanup synced and permanently failed scans
      await _db.deleteSyncedScans();
      
      _isSyncing = false;
      
      final totalProcessed = totalSynced + totalDuplicates + totalErrors;
      
      if (totalProcessed == 0) {
        // Check if API calls failed entirely (scans exist but couldn't be sent)
        if (!parsedResult.success || !unparsedResult.success) {
          final errorMsg = parsedResult.message.isNotEmpty
              ? parsedResult.message
              : unparsedResult.message;
          return SyncResult(
            success: false,
            message: errorMsg.isNotEmpty ? errorMsg : 'Erreur de synchronisation',
          );
        }
        return SyncResult(
          success: true,
          message: 'Aucun scan à synchroniser',
          syncedCount: 0,
        );
      }
      
      // Build descriptive message based on actual results
      String message;
      bool success;
      
      if (totalErrors > 0 && totalSynced == 0 && totalDuplicates == 0) {
        success = false;
        message = '$totalErrors erreur(s) de synchronisation';
      } else if (totalSynced > 0 && totalErrors > 0) {
        success = true;
        message = '$totalSynced synchronisé(s), $totalErrors erreur(s)';
      } else if (totalSynced > 0) {
        success = true;
        message = '$totalSynced scan(s) synchronisé(s)';
        if (totalDuplicates > 0) {
          message += ', $totalDuplicates doublon(s)';
        }
      } else {
        success = true;
        message = 'Synchronisation terminée';
        if (totalDuplicates > 0) {
          message = '$totalDuplicates doublon(s) détecté(s)';
        }
      }
      
      return SyncResult(
        success: success,
        message: message,
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
  
  /// Extract DGI data for unparsed scans, then sync via /sync-parsed endpoint.
  /// This handles the case where scans were saved offline without DGI data,
  /// and now we're online and can extract the data before sending to server.
  Future<SyncResult> _extractAndSyncUnparsedScans() async {
    final pendingScans = await _db.getUnparsedPendingScans();
    if (pendingScans.isEmpty) {
      return SyncResult(success: true, message: '', syncedCount: 0);
    }
    
    final scansToSync = <Map<String, dynamic>>[];
    final scanDbIds = <int>[];
    int extractionErrors = 0;
    
    // Extract DGI data for each unparsed scan
    for (int i = 0; i < pendingScans.length; i++) {
      final scan = pendingScans[i];
      final qrUrl = scan['qr_url'] as String? ?? '';
      final scanId = scan['id'] as int;
      
      if (qrUrl.isEmpty) {
        await _db.markScanFailed(scanId, 'URL manquante');
        extractionErrors++;
        continue;
      }
      
      onProgress?.call(
        'Extraction DGI ${i + 1}/${pendingScans.length}...',
      );
      
      // Try to extract DGI data now that we're online
      try {
        final extractionResult = await _extractor.extractFromUrl(
          qrUrl,
          onProgress: (msg) {
            onProgress?.call(
              'Scan ${i + 1}/${pendingScans.length}: $msg',
            );
          },
        ).timeout(
          const Duration(seconds: 20),
          onTimeout: () => DgiExtractionResult(
            success: false,
            error: 'Timeout extraction DGI',
          ),
        );
        
        if (extractionResult.success && extractionResult.data != null) {
          final data = extractionResult.data!;
          
          // Update the local DB to mark as parsed (in case sync fails, we won't re-extract)
          await _db.updateScanWithParsedData(scanId, data);
          
          scansToSync.add({
            'qr_url': qrUrl,
            'scanned_at': scan['scanned_at'],
            'parsed_data': {
              'supplier_name': data.supplierName,
              'supplier_code_dgi': data.supplierCodeDgi,
              'customer_name': data.customerName,
              'customer_code_dgi': data.customerCodeDgi,
              'invoice_number_dgi': data.invoiceNumberDgi,
              'invoice_date': data.invoiceDate,
              'verification_id': data.verificationId,
              'amount_ttc': data.amountTtc,
            },
          });
          scanDbIds.add(scanId);
        } else {
          // Extraction failed - mark as failed so user knows
          await _db.markScanFailed(
            scanId,
            'Extraction DGI échouée: ${extractionResult.error ?? "données insuffisantes"}. '
            'Veuillez rescanner cette facture.',
          );
          extractionErrors++;
        }
      } catch (e) {
        await _db.markScanFailed(
          scanId,
          'Erreur extraction: ${e.toString()}. Veuillez rescanner cette facture.',
        );
        extractionErrors++;
      }
    }
    
    // If no scans could be extracted, return errors
    if (scansToSync.isEmpty) {
      return SyncResult(
        success: extractionErrors == 0,
        message: extractionErrors > 0 
            ? '$extractionErrors scan(s) non extractible(s)'
            : '',
        errorCount: extractionErrors,
      );
    }
    
    // Send extracted scans to server via /sync-parsed
    onProgress?.call('Envoi de ${scansToSync.length} scan(s) au serveur...');
    final response = await _api.syncParsedScans(scansToSync);
    
    if (response.success && response.data != null) {
      final results = response.data!['results'] as List? ?? [];
      final summary = response.data!['summary'] as Map<String, dynamic>? ?? {};
      
      // Mark scans based on results
      for (int i = 0; i < results.length && i < scanDbIds.length; i++) {
        final result = results[i] as Map<String, dynamic>;
        final scanId = scanDbIds[i];
        
        if (result['success'] == true || result['error_code'] == 'DUPLICATE') {
          await _db.markScanSynced(scanId);
        } else {
          await _db.markScanFailed(
            scanId,
            result['error']?.toString() ?? 'Erreur inconnue',
          );
        }
      }
      
      return SyncResult(
        success: true,
        message: '',
        syncedCount: (summary['successful'] as int?) ?? 0,
        duplicateCount: (summary['duplicates'] as int?) ?? 0,
        errorCount: ((summary['errors'] as int?) ?? 0) + extractionErrors,
      );
    }
    
    return SyncResult(
      success: false,
      message: response.errorMessage ?? 'Erreur sync',
      errorCount: extractionErrors,
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
