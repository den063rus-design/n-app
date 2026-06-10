class User {
  final int id;
  final String fio;
  final int age;
  final String login;
  final String role;
  final String status;

  User({
    required this.id,
    required this.fio,
    required this.age,
    required this.login,
    required this.role,
    required this.status,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      fio: json['fio'] as String,
      age: json['age'] as int,
      login: json['login'] as String,
      role: json['role'] as String,
      status: json['status'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fio': fio,
      'age': age,
      'login': login,
      'role': role,
      'status': status,
    };
  }

  bool get isAdmin => role == 'ADMIN';
  bool get isActive => status == 'ACTIVE';
  bool get isBlocked => status == 'BLOCKED';
  bool get isArchived => status == 'ARCHIVED';
}