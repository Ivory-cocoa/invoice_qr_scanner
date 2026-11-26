import 'package:facture_scanner/core/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

/// Libellé du profil : celui du serveur quand il l'envoie (« Secrétariat »
/// pour qui vérifie ET traite), sinon celui déduit du rôle.
void main() {
  Map<String, dynamic> json(String role, {String? label}) => {
    'id': 7,
    'name': 'Awa',
    'email': 'awa@example.com',
    'login': 'awa',
    'role': role,
    if (label != null) 'role_label': label,
  };

  test('le libellé du serveur prime', () {
    final user = User.fromJson(json('manager', label: 'Secrétariat'));
    expect(user.roleLabel, 'Secrétariat');
    expect(user.isVerificateur, isTrue);
    expect(user.isTraiteur, isTrue);
  });

  test('serveur ancien : libellé déduit du rôle', () {
    expect(User.fromJson(json('manager')).roleLabel, 'Responsable');
    expect(User.fromJson(json('ot_manager')).roleLabel, 'Gestionnaire OT');
    expect(
      User.fromJson(json('manager', label: '  ')).roleLabel,
      'Responsable',
    );
  });

  test('le libellé survit à la mise en cache de la session', () {
    final user = User.fromJson(json('manager', label: 'Secrétariat'));
    expect(User.fromJson(user.toJson()).roleLabel, 'Secrétariat');
  });
}
