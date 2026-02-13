/// User Model
class User {
  final int id;
  final String name;
  final String email;
  final String login;
  final String role; // 'verificateur', 'traiteur', 'manager', 'user'
  
  User({
    required this.id,
    required this.name,
    required this.email,
    required this.login,
    this.role = 'user',
  });
  
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      login: json['login'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'login': login,
      'role': role,
    };
  }
  
  bool get isVerificateur => role == 'verificateur' || role == 'manager';
  bool get isTraiteur => role == 'traiteur' || role == 'manager';
  bool get isManager => role == 'manager';
  
  String get roleLabel {
    switch (role) {
      case 'verificateur': return 'Vérificateur';
      case 'traiteur': return 'Traiteur';
      case 'manager': return 'Responsable';
      default: return 'Utilisateur';
    }
  }
  
  @override
  String toString() => 'User($name - $roleLabel)';
}
