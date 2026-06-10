class User {
  final int id;
  final String username;
  final String role;
  final String? email;
  final bool isActive;
  final DateTime? createdAt;

  User({
    required this.id,
    required this.username,
    required this.role,
    this.email,
    this.isActive = true,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      username: json['username'] as String,
      role: json['role'] as String? ?? 'user',
      email: json['email'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'role': role,
      'email': email,
      'isActive': isActive,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  bool get isAdmin => role == 'admin';
}