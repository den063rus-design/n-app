class AppNotification {
  final int id;
  final int userId;
  final String type; // 'MESSAGE' | 'CALL'
  final String title;
  final String? body;
  final bool isRead;
  final String createdAt;

  AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    this.body,
    this.isRead = false,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as int,
        userId: json['userId'] as int,
        type: json['type'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String?,
        isRead: json['isRead'] as bool? ?? false,
        createdAt: json['createdAt'] as String? ?? DateTime.now().toIso8601String(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'type': type,
        'title': title,
        'body': body,
        'isRead': isRead,
        'createdAt': createdAt,
      };
}