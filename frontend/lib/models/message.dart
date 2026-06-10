class Message {
  final int? id;
  final int senderId;
  final int receiverId;
  final String text;
  final DateTime? createdAt;
  final String status;

  Message({
    this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    this.createdAt,
    this.status = 'SENT',
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as int?,
      senderId: json['senderId'] as int,
      receiverId: json['receiverId'] as int,
      text: json['text'] as String,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      status: json['status'] as String? ?? 'SENT',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      'status': status,
    };
  }

  bool get isRead => status == 'READ';
  bool get isDelivered => status == 'DELIVERED';
  bool get isSent => status == 'SENT';
}