/// User Model
library;

class User {
  final int id;
  final String name;
  final String email;
  final String login;
  final String
  role; // 'verificateur', 'traiteur', 'manager', 'ot_manager', 'user'
  final bool isOtManager;

  /// Libellé du profil envoyé par le serveur (« Secrétariat »,
  /// « Responsable »…). Vide avec un serveur ancien : l'application retombe
  /// alors sur le libellé déduit du rôle.
  final String serverRoleLabel;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.login,
    this.role = 'user',
    this.isOtManager = false,
    this.serverRoleLabel = '',
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final isOtMgrFlag = json['is_ot_manager'] as bool? ?? false;
    final role = json['role'] as String? ?? 'user';
    return User(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      login: json['login'] as String? ?? '',
      role: role,
      // role 'ot_manager' implique le flag, même si un ancien backend ne le renvoyait pas
      isOtManager: isOtMgrFlag || role == 'ot_manager',
      serverRoleLabel: (json['role_label'] as String? ?? '').trim(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'login': login,
      'role': role,
      'is_ot_manager': isOtManager,
      'role_label': serverRoleLabel,
    };
  }

  bool get isVerificateur => role == 'verificateur' || role == 'manager';
  bool get isTraiteur => role == 'traiteur' || role == 'manager';
  bool get isManager => role == 'manager';
  bool get isOtManagerOnly => role == 'ot_manager';

  String get roleLabel {
    if (serverRoleLabel.isNotEmpty) return serverRoleLabel;
    switch (role) {
      case 'verificateur':
        return 'Vérificateur';
      case 'traiteur':
        return 'Traiteur';
      case 'manager':
        return 'Responsable';
      case 'ot_manager':
        return 'Gestionnaire OT';
      default:
        return 'Utilisateur';
    }
  }

  @override
  String toString() => 'User($name - $roleLabel)';
}
