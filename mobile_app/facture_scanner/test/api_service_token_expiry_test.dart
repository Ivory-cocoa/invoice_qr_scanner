/// Tests du traitement de la date d'expiration du token.
///
/// Le piège central : `fields.Datetime` d'Odoo est de l'UTC NAÏF. Une date
/// sans marqueur de fuseau interprétée en heure locale décalerait l'expiration
/// du décalage horaire de l'appareil — invisible en Côte d'Ivoire (UTC+0),
/// bien réel ailleurs.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:facture_scanner/core/services/api_service.dart';

void main() {
  group('parseServerDate', () {
    test('interprète une date suffixée Z comme de l\'UTC', () {
      final parsed = ApiService.parseServerDate('2026-07-28T16:00:00Z');

      expect(parsed, isNotNull);
      expect(parsed!.isUtc, isTrue);
      expect(parsed.hour, 16);
    });

    test('traite une date SANS fuseau comme de l\'UTC, pas comme locale', () {
      // Format émis par les versions antérieures du serveur.
      final parsed = ApiService.parseServerDate('2026-07-28T16:00:00');

      expect(parsed, isNotNull);
      expect(parsed!.isUtc, isTrue,
          reason: 'Une date naïve d\'Odoo doit être forcée en UTC');
      expect(parsed.hour, 16,
          reason: 'L\'heure ne doit pas être décalée par le fuseau local');
    });

    test('les deux formats désignent le même instant', () {
      final withZ = ApiService.parseServerDate('2026-07-28T16:00:00Z');
      final without = ApiService.parseServerDate('2026-07-28T16:00:00');

      expect(without!.isAtSameMomentAs(withZ!), isTrue);
    });

    test('retourne null pour une entrée absente ou invalide', () {
      expect(ApiService.parseServerDate(null), isNull);
      expect(ApiService.parseServerDate(''), isNull);
      expect(ApiService.parseServerDate('pas une date'), isNull);
    });

    test('conserve les microsecondes émises par isoformat()', () {
      final parsed = ApiService.parseServerDate('2026-07-28T16:00:00.123456');

      expect(parsed, isNotNull);
      expect(parsed!.isUtc, isTrue);
      expect(parsed.millisecond, 123);
    });
  });
}
