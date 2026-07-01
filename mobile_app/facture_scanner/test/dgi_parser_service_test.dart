// Tests unitaires du service de parsing DGI (logique pure, sans dépendances).
//
// Couvre : extraction d'UUID, validation d'URL DGI, conversion de dates et
// extraction structurée depuis le texte d'une page DGI.

import 'package:flutter_test/flutter_test.dart';
import 'package:facture_scanner/core/services/dgi_parser_service.dart';

void main() {
  final parser = DgiParserService();

  group('extractUuidFromUrl', () {
    test('extrait un UUID valide depuis une URL DGI', () {
      const url =
          'https://services.fne.dgi.gouv.ci/facture/9f8b2c1a-1234-4abc-8def-0123456789ab';
      expect(
        parser.extractUuidFromUrl(url),
        '9f8b2c1a-1234-4abc-8def-0123456789ab',
      );
    });

    test('normalise l\'UUID en minuscules', () {
      const url =
          'https://services.fne.dgi.gouv.ci/facture/9F8B2C1A-1234-4ABC-8DEF-0123456789AB';
      expect(
        parser.extractUuidFromUrl(url),
        '9f8b2c1a-1234-4abc-8def-0123456789ab',
      );
    });

    test('retourne null quand aucun UUID n\'est présent', () {
      expect(parser.extractUuidFromUrl('https://exemple.com/pas-d-uuid'), isNull);
    });

    test('retourne null pour une chaîne vide', () {
      expect(parser.extractUuidFromUrl(''), isNull);
    });
  });

  group('isValidDgiUrl', () {
    test('accepte le domaine officiel DGI', () {
      expect(
        parser.isValidDgiUrl('https://services.fne.dgi.gouv.ci/facture/abc'),
        isTrue,
      );
    });

    test('rejette un domaine non DGI', () {
      expect(parser.isValidDgiUrl('https://exemple.com/facture/abc'), isFalse);
    });

    test('rejette une chaîne vide', () {
      expect(parser.isValidDgiUrl(''), isFalse);
    });
  });

  group('parseDateToIso', () {
    test('convertit DD/MM/YYYY en ISO YYYY-MM-DD', () {
      expect(parser.parseDateToIso('05/03/2024'), '2024-03-05');
    });

    test('retourne null pour un format invalide', () {
      expect(parser.parseDateToIso('2024-03-05'), isNull);
    });

    test('retourne null pour null', () {
      expect(parser.parseDateToIso(null), isNull);
    });

    test('retourne null pour une date non numérique', () {
      expect(parser.parseDateToIso('aa/bb/cccc'), isNull);
    });
  });

  group('extractFromText', () {
    test('retourne null pour un texte vide', () {
      expect(parser.extractFromText('   '), isNull);
    });

    test('extrait fournisseur, client et identifiant de vérification', () {
      const text = '''
FOURNISSEUR: SOCIETE ALPHA - CI12345
CLIENT: ENTREPRISE BETA - CI67890
Identifiant de vérification: 9f8b2c1a-1234-4abc-8def-0123456789ab
''';
      final data = parser.extractFromText(text);
      expect(data, isNotNull);
      expect(data!.supplierName, 'SOCIETE ALPHA');
      expect(data.supplierCodeDgi, 'CI12345');
      expect(data.customerName, 'ENTREPRISE BETA');
      expect(data.customerCodeDgi, 'CI67890');
    });
  });
}
