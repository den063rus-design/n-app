class User {
  final int id;
  final String fullName;
  final int? age;
  final String role; // 'ADMIN' | 'USER'
  final String status; // 'ACTIVE' | 'BLOCKED' | 'ARCHIVED'
  final String? notes;
  final bool isOnline;
  final String? lastSeenAt;
  final String createdAt;
  final String? login; // только для отображения

  User({
    required this.id,
    required this.fullName,
    this.age,
    required this.role,
    required this.status,
    this.notes,
    this.isOnline = false,
    this.lastSeenAt,
    required this.createdAt,
    this.login,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as int,
        fullName: json['fullName'] as String? ?? json['fio'] as String,
        age: json['age'] as int?,
        role: json['role'] as String,
        status: json['status'] as String,
        notes: json['notes'] as String?,
        isOnline: json['isOnline'] as bool? ?? false,
        lastSeenAt: json['lastSeenAt'] as String?,
        createdAt: json['createdAt'] as String,
        login: json['login'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'fullName': fullName,
        'age': age,
        'role': role,
        'status': status,
        'notes': notes,
        'isOnline': isOnline,
        'lastSeenAt': lastSeenAt,
        'createdAt': createdAt,
        'login': login,
      };

  bool get isAdmin => role == 'ADMIN';
  bool get isActive => status == 'ACTIVE';
  bool get isBlocked => status == 'BLOCKED';
  bool get isArchived => status == 'ARCHIVED';
}