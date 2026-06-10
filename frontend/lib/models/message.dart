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
        url: json['url'] as String? ?? '',
        type: _normalizeAttachmentType(
          json['type'] as String? ?? json['fileType'] as String? ?? '',
          json['fileName'] as String? ?? json['name'] as String? ?? json['key'] as String? ?? '',
        ),
        fileName: json['fileName'] as String? ?? json['name'] as String? ?? json['key'] as String? ?? '',
      );

  static String _normalizeAttachmentType(String rawType, String fileName) {
    final loweredType = rawType.toLowerCase();
    if (loweredType.startsWith('image/')) {
      return 'image';
    }
    if (loweredType.startsWith('video/')) {
      return 'video';
    }
    if (loweredType.startsWith('audio/')) {
      return 'audio';
    }
    if (loweredType == 'application/pdf') {
      return 'document';
    }
    if (loweredType.isNotEmpty &&
        loweredType != 'application/octet-stream' &&
        loweredType != 'binary/octet-stream') {
      return 'document';
    }

    final extension = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    switch (extension) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'heic':
        return 'image';
      case 'mp4':
      case 'mov':
      case 'mkv':
      case 'webm':
      case 'avi':
        return 'video';
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'aac':
      case 'ogg':
      case 'flac':
        return 'audio';
      default:
        return 'document';
    }
  }

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
        content: (json['content'] as String?) ?? (json['text'] as String? ?? ''),
        status: json['status'] as String? ?? 'SENT',
        attachments: json['attachments'] != null
            ? (json['attachments'] as List)
                .map((a) => Attachment.fromJson(a as Map<String, dynamic>))
                .toList()
            : null,
        createdAt: json['createdAt'] as String? ?? DateTime.now().toIso8601String(),
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
