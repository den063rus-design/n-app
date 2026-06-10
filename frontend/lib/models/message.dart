class Attachment {
  final int id;
  final String url;
  final String type;
  final String fileName;

  Attachment({
    required this.id,
    required this.url,
    required this.type,
    required this.fileName,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: json['id'] as int,
        url: json['url'] as String,
        type: json['type'] as String,
        fileName: json['fileName'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'type': type,
        'fileName': fileName,
      };
}

class Message {
  final int id;
  final int senderId;
  final int receiverId;
  final String content;
  final String status; // 'SENT' | 'DELIVERED' | 'READ'
  final List<Attachment>? attachments;
  final String createdAt;

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.status,
    this.attachments,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as int,
        senderId: json['senderId'] as int,
        receiverId: json['receiverId'] as int,
        content: json['content'] as String? ?? json['text'] as String,
        status: json['status'] as String? ?? 'SENT',
        attachments: json['attachments'] != null
            ? (json['attachments'] as List)
                .map((a) => Attachment.fromJson(a as Map<String, dynamic>))
                .toList()
            : null,
        createdAt: json['createdAt'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'receiverId': receiverId,
        'content': content,
        'status': status,
        if (attachments != null)
          'attachments': attachments!.map((a) => a.toJson()).toList(),
        'createdAt': createdAt,
      };

  bool get isRead => status == 'READ';
  bool get isDelivered => status == 'DELIVERED';
  bool get isSent => status == 'SENT';
}