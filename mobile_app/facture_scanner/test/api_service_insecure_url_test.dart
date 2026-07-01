// Tests unitaires du helper de sécurité ApiService.isInsecureUrl.
//
// Vérifie qu'une URL http:// publique est signalée comme non sécurisée,
// tandis que https:// et les adresses de réseau local sont tolérées.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:facture_scanner/core/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // ApiService persiste l'URL dans SharedPreferences → mock en mémoire.
    SharedPreferences.setMockInitialValues({});
  });

  group('isInsecureUrl', () {
    test('signale une URL http:// publique comme non sécurisée', () async {
      final api = ApiService();
      await api.setBaseUrl('http://odoo.exemple.com');
      expect(api.isInsecureUrl, isTrue);
    });

    test('tolère une URL https://', () async {
      final api = ApiService();
      await api.setBaseUrl('https://odoo.ivorycocoa.ci');
      expect(api.isInsecureUrl, isFalse);
    });

    test('tolère localhost en http://', () async {
      final api = ApiService();
      await api.setBaseUrl('http://localhost:8069');
      expect(api.isInsecureUrl, isFalse);
    });

    test('tolère une IP de réseau local en http://', () async {
      final api = ApiService();
      await api.setBaseUrl('http://192.168.1.50:8069');
      expect(api.isInsecureUrl, isFalse);
    });

    test('supprime la barre oblique finale de l\'URL', () async {
      final api = ApiService();
      await api.setBaseUrl('https://odoo.ivorycocoa.ci/');
      expect(api.baseUrl, 'https://odoo.ivorycocoa.ci');
    });
  });
}
