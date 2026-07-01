/// Local Database Service for Offline Support
/// Uses SQLite to store scans when offline
/// Auto-cleanup of data older than 24 hours

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/scan_record.dart';
import 'dgi_parser_service.dart';

class DatabaseService {
  static Database? _database;
  
  // Durée maximale de conservation des données offline (24 heures)
  static const int maxOfflineHours = 24;
  
  // Singleton
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();
  
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await init();
    return _database!;
  }
  
  /// Initialize the database
  Future<Database> init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'facture_scanner.db');
    
    final db = await openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    
    // Nettoyage automatique des données > 24h au démarrage
    await cleanupOldData(db);
    
    return db;
  }
  
  Future<void> _onCreate(Database db, int version) async {
    // Pending scans table (for offline scans with parsed DGI data)
    await db.execute('''
      CREATE TABLE pending_scans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        qr_url TEXT NOT NULL,
        qr_uuid TEXT NOT NULL,
        scanned_at TEXT NOT NULL,
        synced INTEGER DEFAULT 0,
        sync_error TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        supplier_name TEXT,
        supplier_code_dgi TEXT,
        customer_name TEXT,
        customer_code_dgi TEXT,
        invoice_number_dgi TEXT,
        invoice_date TEXT,
        verification_id TEXT,
        amount_ttc REAL,
        raw_text TEXT,
        parsed INTEGER DEFAULT 0
      )
    ''');

    // Sync settings table
    await db.execute('''
      CREATE TABLE sync_settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_hour INTEGER DEFAULT 20,
        sync_minute INTEGER DEFAULT 0,
        auto_sync_enabled INTEGER DEFAULT 1,
        last_scheduled_sync TEXT,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Insert default settings
    await db.insert('sync_settings', {
      'sync_hour': 20,
      'sync_minute': 0,
      'auto_sync_enabled': 1,
    });
    
    // Scan history cache table
    await db.execute('''
      CREATE TABLE scan_history (
        id INTEGER PRIMARY KEY,
        reference TEXT,
        qr_uuid TEXT,
        supplier_name TEXT,
        supplier_code_dgi TEXT,
        invoice_number_dgi TEXT,
        invoice_date TEXT,
        amount_ttc REAL,
        currency TEXT DEFAULT 'XOF',
        state TEXT,
        state_label TEXT,
        invoice_id INTEGER,
        invoice_name TEXT,
        invoice_state TEXT,
        scan_date TEXT,
        scanned_by TEXT,
        error_message TEXT,
        duplicate_count INTEGER DEFAULT 0,
        last_duplicate_attempt TEXT,
        last_duplicate_user TEXT,
        reprocess_attempt_count INTEGER DEFAULT 0,
        last_reprocess_attempt TEXT,
        last_reprocess_user TEXT,
        is_processed INTEGER DEFAULT 0,
        processed_by TEXT,
        processed_by_id INTEGER,
        processed_date TEXT,
        verification_duration REAL DEFAULT 0,
        is_manual_entry INTEGER DEFAULT 0,
        cached_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    
    // Create indexes
    await db.execute('CREATE INDEX idx_pending_synced ON pending_scans(synced)');
    await db.execute('CREATE INDEX idx_pending_uuid ON pending_scans(qr_uuid)');
    await db.execute('CREATE INDEX idx_history_uuid ON scan_history(qr_uuid)');
  }
  
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle migrations here
    if (oldVersion < 2) {
      // Add index for cleanup queries
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_pending_created ON pending_scans(created_at)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_history_cached ON scan_history(cached_at)');
      } catch (_) {}
    }
    if (oldVersion < 3) {
      // Add duplicate tracking columns
      try {
        await db.execute('ALTER TABLE scan_history ADD COLUMN duplicate_count INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE scan_history ADD COLUMN last_duplicate_attempt TEXT');
        await db.execute('ALTER TABLE scan_history ADD COLUMN last_duplicate_user TEXT');
      } catch (_) {}
    }
    if (oldVersion < 4) {
      // Add parsed DGI data columns to pending_scans
      try {
        await db.execute('ALTER TABLE pending_scans ADD COLUMN supplier_name TEXT');
        await db.execute('ALTER TABLE pending_scans ADD COLUMN supplier_code_dgi TEXT');
        await db.execute('ALTER TABLE pending_scans ADD COLUMN customer_name TEXT');
        await db.execute('ALTER TABLE pending_scans ADD COLUMN customer_code_dgi TEXT');
        await db.execute('ALTER TABLE pending_scans ADD COLUMN invoice_number_dgi TEXT');
        await db.execute('ALTER TABLE pending_scans ADD COLUMN invoice_date TEXT');
        await db.execute('ALTER TABLE pending_scans ADD COLUMN verification_id TEXT');
        await db.execute('ALTER TABLE pending_scans ADD COLUMN amount_ttc REAL');
        await db.execute('ALTER TABLE pending_scans ADD COLUMN raw_text TEXT');
        await db.execute('ALTER TABLE pending_scans ADD COLUMN parsed INTEGER DEFAULT 0');
      } catch (_) {}
      // Create sync_settings table
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sync_settings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sync_hour INTEGER DEFAULT 20,
            sync_minute INTEGER DEFAULT 0,
            auto_sync_enabled INTEGER DEFAULT 1,
            last_scheduled_sync TEXT,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
          )
        ''');
        await db.insert('sync_settings', {
          'sync_hour': 20,
          'sync_minute': 0,
          'auto_sync_enabled': 1,
        });
      } catch (_) {}
    }
    if (oldVersion < 5) {
      // Colonnes manquantes du cache d'historique : sans elles, la mise en
      // cache lève "no column named ..." et vide l'historique affiché.
      const historyColumns = <String>[
        'ALTER TABLE scan_history ADD COLUMN reprocess_attempt_count INTEGER DEFAULT 0',
        'ALTER TABLE scan_history ADD COLUMN last_reprocess_attempt TEXT',
        'ALTER TABLE scan_history ADD COLUMN last_reprocess_user TEXT',
        'ALTER TABLE scan_history ADD COLUMN is_processed INTEGER DEFAULT 0',
        'ALTER TABLE scan_history ADD COLUMN processed_by TEXT',
        'ALTER TABLE scan_history ADD COLUMN processed_by_id INTEGER',
        'ALTER TABLE scan_history ADD COLUMN processed_date TEXT',
        'ALTER TABLE scan_history ADD COLUMN verification_duration REAL DEFAULT 0',
        'ALTER TABLE scan_history ADD COLUMN is_manual_entry INTEGER DEFAULT 0',
      ];
      for (final stmt in historyColumns) {
        try {
          await db.execute(stmt);
        } catch (_) {
          // Colonne déjà présente : ignorer.
        }
      }
    }
  }
  
  /// Nettoyer les données de plus de 24 heures
  Future<void> cleanupOldData([Database? providedDb]) async {
    final db = providedDb ?? await database;
    final cutoffTime = DateTime.now().subtract(const Duration(hours: maxOfflineHours));
    final cutoffString = cutoffTime.toIso8601String();
    
    // Supprimer les scans en attente de plus de 24h (déjà synchronisés ou non)
    await db.delete(
      'pending_scans',
      where: 'created_at < ?',
      whereArgs: [cutoffString],
    );
    
    // Supprimer le cache d'historique de plus de 24h
    await db.delete(
      'scan_history',
      where: 'cached_at < ?',
      whereArgs: [cutoffString],
    );
  }
  
  // ==================== PENDING SCANS ====================
  
  /// Add a pending scan (offline mode)
  Future<int> addPendingScan(String qrUrl, String qrUuid) async {
    final db = await database;
    return await db.insert('pending_scans', {
      'qr_url': qrUrl,
      'qr_uuid': qrUuid,
      'scanned_at': DateTime.now().toIso8601String(),
      'synced': 0,
      'parsed': 0,
    });
  }

  /// Add a pending scan with parsed DGI data (local extraction mode)
  Future<int> addParsedPendingScan(
    String qrUrl,
    String qrUuid,
    DgiParsedData parsedData,
  ) async {
    final db = await database;
    return await db.insert('pending_scans', {
      'qr_url': qrUrl,
      'qr_uuid': qrUuid,
      'scanned_at': DateTime.now().toIso8601String(),
      'synced': 0,
      'parsed': 1,
      'supplier_name': parsedData.supplierName,
      'supplier_code_dgi': parsedData.supplierCodeDgi,
      'customer_name': parsedData.customerName,
      'customer_code_dgi': parsedData.customerCodeDgi,
      'invoice_number_dgi': parsedData.invoiceNumberDgi,
      'invoice_date': parsedData.invoiceDate,
      'verification_id': parsedData.verificationId,
      'amount_ttc': parsedData.amountTtc,
      'raw_text': parsedData.rawText,
    });
  }
  
  /// Get all pending (unsynced) scans
  Future<List<Map<String, dynamic>>> getPendingScans() async {
    final db = await database;
    return await db.query(
      'pending_scans',
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'created_at ASC',
    );
  }
  
  /// Mark scan as synced
  Future<void> markScanSynced(int id) async {
    final db = await database;
    await db.update(
      'pending_scans',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  /// Mark scan as permanently failed with error (synced=2)
  Future<void> markScanFailed(int id, String error) async {
    final db = await database;
    await db.update(
      'pending_scans',
      {'synced': 2, 'sync_error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  /// Check if QR code exists in pending scans
  Future<bool> isPendingScan(String qrUuid) async {
    final db = await database;
    final result = await db.query(
      'pending_scans',
      where: 'qr_uuid = ?',
      whereArgs: [qrUuid],
      limit: 1,
    );
    return result.isNotEmpty;
  }
  
  /// Get pending scans count
  Future<int> getPendingScansCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM pending_scans WHERE synced = 0'
    );
    return result.first['count'] as int? ?? 0;
  }
  
  /// Delete synced and permanently failed scans (cleanup)
  Future<void> deleteSyncedScans() async {
    final db = await database;
    await db.delete(
      'pending_scans',
      where: 'synced != ?',
      whereArgs: [0],
    );
  }
  
  /// Update an unparsed scan with extracted DGI data (convert parsed=0 → parsed=1)
  /// Used during sync when we extract DGI data for previously unparsed scans.
  Future<void> updateScanWithParsedData(int id, DgiParsedData data) async {
    final db = await database;
    await db.update(
      'pending_scans',
      {
        'parsed': 1,
        'supplier_name': data.supplierName,
        'supplier_code_dgi': data.supplierCodeDgi,
        'customer_name': data.customerName,
        'customer_code_dgi': data.customerCodeDgi,
        'invoice_number_dgi': data.invoiceNumberDgi,
        'invoice_date': data.invoiceDate,
        'verification_id': data.verificationId,
        'amount_ttc': data.amountTtc,
        'raw_text': data.rawText,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== SCAN HISTORY CACHE ====================
  
  /// Cache scan history from server
  Future<void> cacheScanHistory(List<ScanRecord> records) async {
    final db = await database;
    final batch = db.batch();
    
    for (final record in records) {
      batch.insert(
        'scan_history',
        _sanitizeForSqlite(record.toMap()),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    
    // continueOnError : une ligne problématique ne doit pas faire échouer
    // tout le lot ni propager une exception jusqu'à l'appelant.
    await batch.commit(noResult: true, continueOnError: true);
  }
  
  /// Convertit une map pour un stockage SQLite sûr : sqflite n'accepte que
  /// num / String / Uint8List / null. Les booléens (is_processed,
  /// is_manual_entry) sont convertis en 0/1.
  Map<String, dynamic> _sanitizeForSqlite(Map<String, dynamic> map) {
    return map.map((key, value) {
      if (value is bool) return MapEntry(key, value ? 1 : 0);
      return MapEntry(key, value);
    });
  }
  
  /// Get cached scan history
  Future<List<ScanRecord>> getCachedHistory({int limit = 50}) async {
    final db = await database;
    final results = await db.query(
      'scan_history',
      orderBy: 'scan_date DESC',
      limit: limit,
    );
    
    // Ignorer silencieusement une éventuelle ligne corrompue plutôt que de
    // faire échouer tout le chargement de l'historique.
    final records = <ScanRecord>[];
    for (final map in results) {
      try {
        records.add(ScanRecord.fromMap(map));
      } catch (_) {
        // Ligne illisible : on la saute.
      }
    }
    return records;
  }
  
  /// Check if QR code exists in history cache
  Future<ScanRecord?> findInHistoryCache(String qrUuid) async {
    final db = await database;
    final result = await db.query(
      'scan_history',
      where: 'qr_uuid = ?',
      whereArgs: [qrUuid],
      limit: 1,
    );
    
    if (result.isEmpty) return null;
    return ScanRecord.fromMap(result.first);
  }
  
  /// Clear history cache
  Future<void> clearHistoryCache() async {
    final db = await database;
    await db.delete('scan_history');
  }
  
  // ==================== UTILITIES ====================
  
  /// Get all parsed pending scans (for enriched sync)
  Future<List<Map<String, dynamic>>> getParsedPendingScans() async {
    final db = await database;
    return await db.query(
      'pending_scans',
      where: 'synced = ? AND parsed = ?',
      whereArgs: [0, 1],
      orderBy: 'created_at ASC',
    );
  }

  /// Get all unparsed pending scans (for fallback sync)
  Future<List<Map<String, dynamic>>> getUnparsedPendingScans() async {
    final db = await database;
    return await db.query(
      'pending_scans',
      where: 'synced = ? AND parsed = ?',
      whereArgs: [0, 0],
      orderBy: 'created_at ASC',
    );
  }

  // ==================== SYNC SETTINGS ====================

  /// Get sync settings
  Future<Map<String, dynamic>> getSyncSettings() async {
    final db = await database;
    final results = await db.query('sync_settings', limit: 1);
    if (results.isEmpty) {
      // Insert default and return
      await db.insert('sync_settings', {
        'sync_hour': 20,
        'sync_minute': 0,
        'auto_sync_enabled': 1,
      });
      return {
        'sync_hour': 20,
        'sync_minute': 0,
        'auto_sync_enabled': 1,
      };
    }
    return results.first;
  }

  /// Update sync settings
  Future<void> updateSyncSettings({
    int? syncHour,
    int? syncMinute,
    bool? autoSyncEnabled,
  }) async {
    final db = await database;
    final current = await getSyncSettings();
    await db.update(
      'sync_settings',
      {
        if (syncHour != null) 'sync_hour': syncHour,
        if (syncMinute != null) 'sync_minute': syncMinute,
        if (autoSyncEnabled != null) 'auto_sync_enabled': autoSyncEnabled ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [current['id']],
    );
  }

  /// Record the last scheduled sync time
  Future<void> recordScheduledSync() async {
    final db = await database;
    final current = await getSyncSettings();
    await db.update(
      'sync_settings',
      {
        'last_scheduled_sync': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [current['id']],
    );
  }

  /// Clear all data (logout)
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('pending_scans');
    await db.delete('scan_history');
  }
}
