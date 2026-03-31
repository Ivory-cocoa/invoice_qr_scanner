/// Background Scan Queue Service
/// Gère une file d'attente de scans traités en arrière-plan avec sémaphore.
/// L'utilisateur peut continuer à scanner pendant que l'extraction DGI
/// s'effectue en tâche de fond. Si l'extraction prend trop de temps,
/// l'utilisateur peut ouvrir le formulaire de saisie manuelle.

import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'database_service.dart';
import 'dgi_extractor_service.dart';
import 'dgi_parser_service.dart';
import '../models/scan_record.dart';

/// État d'un scan dans la file d'attente
enum QueueItemState {
  /// En attente de traitement
  pending,
  /// Extraction DGI en cours
  extracting,
  /// Extraction réussie, envoi au serveur en cours
  submitting,
  /// Terminé avec succès (facture créée)
  completed,
  /// Timeout - saisie manuelle requise
  needsManualEntry,
  /// Erreur
  failed,
}

/// Un élément de la file d'attente de scan
class QueueItem {
  final String id;
  final String qrUrl;
  final String qrUuid;
  final DateTime addedAt;
  QueueItemState state;
  String? progressMessage;
  String? resultMessage;
  DgiParsedData? extractedData;
  ScanRecord? scanRecord;
  double verificationDuration;
  String? errorMessage;

  QueueItem({
    required this.id,
    required this.qrUrl,
    required this.qrUuid,
    required this.addedAt,
    this.state = QueueItemState.pending,
    this.progressMessage,
    this.resultMessage,
    this.extractedData,
    this.scanRecord,
    this.verificationDuration = 0,
    this.errorMessage,
  });

  bool get isActive =>
      state == QueueItemState.pending ||
      state == QueueItemState.extracting ||
      state == QueueItemState.submitting;

  bool get isTerminal =>
      state == QueueItemState.completed ||
      state == QueueItemState.needsManualEntry ||
      state == QueueItemState.failed;
}

/// Service de file d'attente avec sémaphore pour traitement en arrière-plan
class BackgroundScanQueue extends ChangeNotifier {
  final ApiService _api = ApiService();
  final DatabaseService _db = DatabaseService();
  final DgiExtractorService _extractor = DgiExtractorService();

  /// File d'attente ordonnée
  final LinkedHashMap<String, QueueItem> _queue = LinkedHashMap();

  /// Sémaphore : max 1 extraction à la fois (WebView unique)
  bool _isProcessing = false;

  /// Timeout configurable (en secondes)
  int _verificationTimeout = 5;

  /// Compteurs de session
  int _sessionSuccessCount = 0;
  int _sessionDuplicateCount = 0;
  int _sessionErrorCount = 0;
  int _sessionManualCount = 0;

  /// Callback pour rafraîchir l'historique côté ScanProvider
  VoidCallback? onHistoryChanged;

  // --- Getters ---

  List<QueueItem> get items => _queue.values.toList();
  List<QueueItem> get activeItems =>
      _queue.values.where((i) => i.isActive).toList();
  List<QueueItem> get completedItems =>
      _queue.values.where((i) => i.state == QueueItemState.completed).toList();
  List<QueueItem> get manualEntryItems =>
      _queue.values.where((i) => i.state == QueueItemState.needsManualEntry).toList();
  List<QueueItem> get failedItems =>
      _queue.values.where((i) => i.state == QueueItemState.failed).toList();

  int get totalCount => _queue.length;
  int get activeCount => activeItems.length;
  int get completedCount => completedItems.length;
  int get needsManualEntryCount => manualEntryItems.length;
  int get failedCount => failedItems.length;
  bool get isProcessing => _isProcessing;
  bool get hasItems => _queue.isNotEmpty;
  bool get hasActiveItems => activeItems.isNotEmpty;
  bool get hasActionNeeded => needsManualEntryCount > 0;

  int get sessionSuccessCount => _sessionSuccessCount;
  int get sessionDuplicateCount => _sessionDuplicateCount;
  int get sessionErrorCount => _sessionErrorCount;
  int get sessionManualCount => _sessionManualCount;

  int get verificationTimeout => _verificationTimeout;

  /// Met à jour le timeout et propage
  set verificationTimeout(int value) {
    _verificationTimeout = value.clamp(1, 60);
  }

  /// Obtenir un item par ID
  QueueItem? getItem(String id) => _queue[id];

  /// Ajouter un scan à la file d'attente et lancer le traitement
  /// Retourne l'ID de l'élément ajouté, ou null si c'est un doublon local
  Future<String?> enqueue(String qrUrl, String qrUuid) async {
    // Vérifier si déjà dans la queue active
    final existingActive = _queue.values.where(
      (i) => i.qrUuid == qrUuid && i.isActive,
    );
    if (existingActive.isNotEmpty) {
      return null; // Déjà en traitement
    }

    final id = '${qrUuid}_${DateTime.now().millisecondsSinceEpoch}';
    final item = QueueItem(
      id: id,
      qrUrl: qrUrl,
      qrUuid: qrUuid,
      addedAt: DateTime.now(),
      progressMessage: 'En file d\'attente...',
    );

    _queue[id] = item;
    notifyListeners();

    // Lancer le traitement si le sémaphore est libre
    _processNext();

    return id;
  }

  /// Traiter le prochain élément dans la file (sémaphore = 1)
  void _processNext() {
    if (_isProcessing) return;

    final nextItem = _queue.values
        .where((i) => i.state == QueueItemState.pending)
        .firstOrNull;

    if (nextItem == null) return;

    _isProcessing = true;
    _processItem(nextItem);
  }

  /// Traiter un élément : extraction DGI + soumission au serveur
  Future<void> _processItem(QueueItem item) async {
    item.state = QueueItemState.extracting;
    item.progressMessage = 'Vérification DGI en cours...';
    notifyListeners();

    final stopwatch = Stopwatch()..start();

    try {
      // Extraction DGI avec timeout
      DgiExtractionResult? result;
      bool timedOut = false;

      try {
        result = await _extractor.extractFromUrl(
          item.qrUrl,
          onProgress: (msg) {
            item.progressMessage = msg;
            notifyListeners();
          },
        ).timeout(
          Duration(seconds: _verificationTimeout),
          onTimeout: () {
            timedOut = true;
            return DgiExtractionResult(
              success: false,
              error: 'Timeout DGI',
            );
          },
        );
      } catch (e) {
        timedOut = true;
        result = DgiExtractionResult(
          success: false,
          error: e.toString(),
        );
      }

      stopwatch.stop();
      item.verificationDuration = stopwatch.elapsedMilliseconds / 1000.0;

      if (result != null && result.success && result.data != null && !timedOut) {
        // Extraction réussie → soumettre au serveur
        item.extractedData = result.data;
        item.state = QueueItemState.submitting;
        item.progressMessage = 'Création de la facture...';
        notifyListeners();

        await _submitToServer(item, result.data!, false);
      } else {
        // Timeout ou échec → requiert saisie manuelle
        item.extractedData = result?.data; // Données partielles éventuelles
        item.state = QueueItemState.needsManualEntry;
        item.progressMessage = null;
        item.resultMessage = timedOut
            ? 'Timeout (${item.verificationDuration.toStringAsFixed(1)}s) - Saisie manuelle requise'
            : 'Extraction échouée - Saisie manuelle requise';
        _sessionManualCount++;
        notifyListeners();
      }
    } catch (e) {
      stopwatch.stop();
      item.verificationDuration = stopwatch.elapsedMilliseconds / 1000.0;
      item.state = QueueItemState.failed;
      item.progressMessage = null;
      item.errorMessage = e.toString();
      item.resultMessage = 'Erreur: ${e.toString()}';
      _sessionErrorCount++;
      notifyListeners();
    }

    // Libérer le sémaphore et traiter le prochain
    _isProcessing = false;
    _processNext();
  }

  /// Soumettre les données extraites au serveur
  Future<void> _submitToServer(QueueItem item, DgiParsedData data, bool isManual) async {
    try {
      final response = await _api.scanWithData(
        qrUrl: item.qrUrl,
        supplierName: data.supplierName,
        supplierCodeDgi: data.supplierCodeDgi,
        customerName: data.customerName,
        customerCodeDgi: data.customerCodeDgi,
        invoiceNumberDgi: data.invoiceNumberDgi,
        invoiceDate: data.invoiceDate,
        amountTtc: data.amountTtc,
        verificationDuration: item.verificationDuration,
        isManualEntry: isManual,
      );

      if (response.success && response.data != null) {
        item.state = QueueItemState.completed;
        item.progressMessage = null;
        item.resultMessage = response.data!['message'] ?? 'Facture créée avec succès';
        if (response.data!.containsKey('record')) {
          item.scanRecord = ScanRecord.fromJson(response.data!['record']);
        }
        _sessionSuccessCount++;
        onHistoryChanged?.call();
      } else if (response.errorCode == 'DUPLICATE') {
        item.state = QueueItemState.completed;
        item.progressMessage = null;
        item.resultMessage = 'Doublon détecté';
        if (response.data != null && response.data!.containsKey('existing_record')) {
          item.scanRecord = ScanRecord.fromJson(response.data!['existing_record']);
        }
        _sessionDuplicateCount++;
      } else {
        item.state = QueueItemState.failed;
        item.progressMessage = null;
        item.errorMessage = response.errorCode;
        item.resultMessage = response.errorMessage ?? 'Erreur serveur';
        _sessionErrorCount++;
      }
    } catch (e) {
      item.state = QueueItemState.failed;
      item.progressMessage = null;
      item.errorMessage = e.toString();
      item.resultMessage = 'Erreur réseau: ${e.toString()}';
      _sessionErrorCount++;
    }

    notifyListeners();
  }

  /// Soumettre la saisie manuelle pour un item en attente
  Future<void> submitManualEntry({
    required String itemId,
    required String supplierName,
    String? supplierCodeDgi,
    String? customerName,
    String? customerCodeDgi,
    required String invoiceNumberDgi,
    String? invoiceDate,
    required double amountTtc,
    required double verificationDuration,
  }) async {
    final item = _queue[itemId];
    if (item == null) return;

    item.state = QueueItemState.submitting;
    item.progressMessage = 'Création de la facture...';
    notifyListeners();

    final data = DgiParsedData(
      supplierName: supplierName,
      supplierCodeDgi: supplierCodeDgi ?? '',
      customerName: customerName ?? '',
      customerCodeDgi: customerCodeDgi ?? '',
      invoiceNumberDgi: invoiceNumberDgi,
      invoiceDate: invoiceDate,
      verificationId: '',
      amountTtc: amountTtc,
      rawText: '',
    );

    item.verificationDuration = verificationDuration;
    await _submitToServer(item, data, true);
  }

  /// Réessayer un item en échec
  void retryItem(String itemId) {
    final item = _queue[itemId];
    if (item == null || !item.isTerminal) return;

    item.state = QueueItemState.pending;
    item.progressMessage = 'En file d\'attente (nouvelle tentative)...';
    item.errorMessage = null;
    item.resultMessage = null;
    notifyListeners();

    _processNext();
  }

  /// Supprimer un item terminé de la file
  void removeItem(String itemId) {
    _queue.remove(itemId);
    notifyListeners();
  }

  /// Supprimer tous les items terminés
  void clearCompleted() {
    _queue.removeWhere((_, item) => item.isTerminal);
    notifyListeners();
  }

  /// Réinitialiser toute la file
  void clear() {
    _queue.clear();
    _isProcessing = false;
    notifyListeners();
  }
}
