import 'package:flutter_test/flutter_test.dart';
import 'package:facture_scanner/core/models/scan_record.dart';
import 'package:facture_scanner/core/services/dgi_parser_service.dart';

/// Avoirs DGI côté application.
///
/// La plateforme FNE certifie les avoirs sous un QR-code de forme identique à
/// celui des factures, et la page de vérification affiche leur montant en
/// VALEUR ABSOLUE. Sans nature explicite portée de bout en bout, l'application
/// affiche un avoir exactement comme une facture — c'est ce qui a permis à des
/// avoirs d'être traités comme des dettes fournisseur pendant des mois.
void main() {
  group('DocumentType', () {
    test('reconnaît « refund » et retombe sur « invoice » sinon', () {
      expect(DocumentType.parse('refund'), DocumentType.refund);
      expect(DocumentType.parse('REFUND'), DocumentType.refund);
      expect(DocumentType.parse('normal'), DocumentType.invoice);
      expect(DocumentType.parse(null), DocumentType.invoice);
      expect(DocumentType.parse(''), DocumentType.invoice);
    });

    test('un type inconnu ne devient JAMAIS un avoir par accident', () {
      // Le défaut sûr est « facture » : un avoir mal typé se voit tout de
      // suite (la comptabilité s'en aperçoit), l'inverse non.
      expect(DocumentType.parse('quelque_chose'), DocumentType.invoice);
    });
  });

  group('ScanRecord — nature et signe', () {
    ScanRecord build({String documentType = 'invoice', double amount = 250000}) {
      return ScanRecord.fromJson({
        'id': 1,
        'reference': 'SCAN/2026/00001',
        'qr_uuid': 'uuid-1',
        'supplier_name': 'PACKING SERVICE INTERNATIONAL',
        'invoice_number_dgi': 'A7603114Y2600000393',
        'amount_ttc': amount,
        'document_type': documentType,
        'currency': 'XOF',
        'state': 'done',
        'state_label': 'Facture créée',
      });
    }

    test('une facture garde un montant positif', () {
      final r = build();
      expect(r.isRefund, isFalse);
      expect(r.amountSigned, 250000);
      expect(r.formattedAmount, '250 000 XOF');
    });

    test('un avoir est stocké positif mais signé négatif', () {
      final r = build(documentType: 'refund');
      expect(r.isRefund, isTrue);
      expect(r.amountTtc, 250000);
      expect(r.amountSigned, -250000);
    });

    test('le montant AFFICHÉ d\'un avoir porte le signe moins', () {
      // Le signe est posé dans le modèle, pas dans chaque écran : un écran
      // oublié ne peut donc pas réintroduire l'ambiguïté.
      expect(build(documentType: 'refund').formattedAmount, '− 250 000 XOF');
    });

    test('un montant négatif reçu du serveur est ramené en absolu', () {
      // Ceinture et bretelles : si un jour le serveur renvoyait un négatif,
      // le combiner avec le type produirait un double négatif.
      final r = build(documentType: 'refund', amount: -250000);
      expect(r.amountTtc, 250000);
      expect(r.amountSigned, -250000);
    });

    test('la nature survit à l\'aller-retour par le cache SQLite', () {
      final r = build(documentType: 'refund');
      final cached = ScanRecord.fromMap(r.toMap());
      expect(cached.isRefund, isTrue);
      expect(cached.amountSigned, -250000);
    });

    test('toMap expose les colonnes de nature de scan_history', () {
      final map = build(documentType: 'refund').toMap();
      for (final key in [
        'document_type',
        'document_type_verified',
        'origin_invoice_number_dgi',
        'origin_scan_reference',
        'refund_count',
      ]) {
        expect(map.containsKey(key), isTrue, reason: 'clé manquante: $key');
      }
    });

    test('une nature non confirmée est signalée sur un scan abouti', () {
      final r = build(documentType: 'refund');
      expect(r.documentTypeVerified, isFalse);
      expect(r.needsTypeConfirmation, isTrue);
    });
  });

  group('DgiParserService — détection d\'un avoir dans le texte', () {
    final parser = DgiParserService();

    test('une facture ordinaire reste une facture', () {
      final data = parser.extractFromText('''
FOURNISSEUR:
TRANSITAIRE EXEMPLE - 2502298K
NUMERO DE FACTURE: 2502298K26000000003
MONTANT TTC: 1 677 566 FCFA
''');
      expect(data, isNotNull);
      expect(data!.documentType, DocumentType.invoice);
      expect(data.amountTtc, 1677566);
    });

    test('un montant négatif suffit à conclure à un avoir', () {
      final data = parser.extractFromText('''
FOURNISSEUR:
PACKING SERVICE INTERNATIONAL - 7603114Y
NUMERO DE FACTURE: A7603114Y2600000393
MONTANT TTC: -250 000 FCFA
''');
      expect(data!.documentType, DocumentType.refund);
      expect(data.amountTtc, 250000, reason: 'stocké en valeur absolue');
      expect(data.formattedAmount, '− 250 000 FCFA');
    });

    test('la référence préfixée « A » suffit aussi', () {
      // Cas réel : la page affiche le montant en valeur absolue, seul le
      // numéro trahit l'avoir.
      final data = parser.extractFromText('''
FOURNISSEUR:
PACKING SERVICE INTERNATIONAL - 7603114Y
NUMERO DE FACTURE: A7603114Y2600000393
MONTANT TTC: 250 000 FCFA
''');
      expect(data!.documentType, DocumentType.refund);
    });

    test('le mot « avoir » dans la page suffit également', () {
      final data = parser.extractFromText('''
AVOIR
FOURNISSEUR:
PACKING SERVICE INTERNATIONAL - 7603114Y
NUMERO DE FACTURE: 7603114Y26000010087
MONTANT TTC: 250 000 FCFA
''');
      expect(data!.documentType, DocumentType.refund);
    });

    test('la nature traverse la sérialisation du cache hors ligne', () {
      final data = parser.extractFromText('''
FOURNISSEUR:
PACKING SERVICE INTERNATIONAL - 7603114Y
NUMERO DE FACTURE: A7603114Y2600000393
MONTANT TTC: 250 000 FCFA
''');
      final round = DgiParsedData.fromMap(data!.toMap());
      expect(round.documentType, DocumentType.refund);
      expect(round.isRefund, isTrue);
    });
  });
}
