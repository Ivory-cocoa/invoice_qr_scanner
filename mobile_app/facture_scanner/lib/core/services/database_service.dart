/// Local Database Service for Offline Support
/// Uses SQLite to store scans when offline
/// Auto-cleanup of data older than 24 hours

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/scan_record.dart';

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
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    
    // Nettoyage automatique des données > 24h au démarrage
    await cleanupOldData(db);
    
    return db;
  }
  
  Future<void> _onCreate(Database db, int version) async {
    // Pending scans table (for offline scans)
    await db.execute('''
      CREATE TABLE pending_scans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        qr_url TEXT NOT NULL,
        qr_uuid TEXT NOT NULL,
        scanned_at TEXT NOT NULL,
        synced INTEGER DEFAULT 0,
        sync_error TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    
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
  
  /// Mark scan as failed with error
  Future<void> markScanFailed(int id, String error) async {
    final db = await database;
    await db.update(
      'pending_scans',
      {'sync_error': error},
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
  
  /// Delete synced scans (cleanup)
  Future<void> deleteSyncedScans() async {
    final db = await database;
    await db.delete(
      'pending_scans',
      where: 'synced = ?',
      whereArgs: [1],
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
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    
    await batch.commit(noResult: true);
  }
  
  /// Get cached scan history
  Future<List<ScanRecord>> getCachedHistory({int limit = 50}) async {
    final db = await database;
    final results = await db.query(
      'scan_history',
      orderBy: 'scan_date DESC',
      limit: limit,
    );
    
    return results.map((map) => ScanRecord.fromMap(map)).toList();
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
  
  /// Clear all data (logout)
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('pending_scans');
    await db.delete('scan_history');
  }
}
