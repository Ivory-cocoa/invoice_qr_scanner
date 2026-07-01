import 'package:flutter_test/flutter_test.dart';
import 'package:facture_scanner/core/models/scan_record.dart';

/// Régression : le cache SQLite (table scan_history) stocke les booléens
/// sous forme d'entiers 0/1. `ScanRecord.fromMap` doit donc accepter les
/// booléens qu'ils soient fournis en `int` (SQLite) ou en `bool`.
void main() {
  group('ScanRecord.fromMap - booléens depuis SQLite (int 0/1)', () {
    Map<String, dynamic> baseRow({
      dynamic isProcessed,
      dynamic isManualEntry,
    }) {
      return {
        'id': 1,
        'reference': 'SCAN/2026/00001',
        'qr_uuid': 'uuid-1',
        'supplier_name': 'ACME',
        'state': 'processed',
        'state_label': 'Traité',
        'amount_ttc': 1000.0,
        'scan_date': '2026-07-01T08:45:01',
        'is_processed': isProcessed,
        'is_manual_entry': isManualEntry,
        'verification_duration': 2.5,
        'reprocess_attempt_count': 0,
        'duplicate_count': 0,
      };
    }

    test('is_processed = 1 (int) -> true', () {
      final r = ScanRecord.fromMap(baseRow(isProcessed: 1, isManualEntry: 0));
      expect(r.isProcessed, isTrue);
      expect(r.isManualEntry, isFalse);
    });

    test('is_processed = 0 (int) -> false', () {
      final r = ScanRecord.fromMap(baseRow(isProcessed: 0, isManualEntry: 1));
      expect(r.isProcessed, isFalse);
      expect(r.isManualEntry, isTrue);
    });

    test('is_processed = true (bool) -> true', () {
      final r =
          ScanRecord.fromMap(baseRow(isProcessed: true, isManualEntry: false));
      expect(r.isProcessed, isTrue);
      expect(r.isManualEntry, isFalse);
    });

    test('is_processed null -> déduit de state == processed', () {
      final r = ScanRecord.fromMap(baseRow(isProcessed: null, isManualEntry: null));
      expect(r.isProcessed, isTrue); // state == 'processed'
      expect(r.isManualEntry, isFalse);
    });
  });

  group('ScanRecord.toMap - clés compatibles cache', () {
    test('contient toutes les clés attendues par la table scan_history', () {
      final r = ScanRecord.fromMap({
        'id': 2,
        'reference': 'SCAN/2026/00002',
        'qr_uuid': 'uuid-2',
        'state': 'done',
        'scan_date': '2026-07-01T09:00:00',
      });
      final map = r.toMap();
      // Ces champs sont désormais des colonnes de scan_history.
      for (final key in [
        'is_processed',
        'is_manual_entry',
        'processed_by',
        'processed_by_id',
        'processed_date',
        'verification_duration',
        'reprocess_attempt_count',
        'last_reprocess_attempt',
        'last_reprocess_user',
      ]) {
        expect(map.containsKey(key), isTrue, reason: 'clé manquante: $key');
      }
    });
  });
}
