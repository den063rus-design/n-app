import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';
import 'attachment_viewer.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isAdmin;
  final bool isMine;
  final VoidCallback? onDelete;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isAdmin,
    required this.isMine,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(
      DateTime.parse(message.createdAt),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Контент сообщения
          Row(
            mainAxisAlignment:
                isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMine && isAdmin)
                _buildDeleteButton(context),
              if (!isMine && !isAdmin)
                const SizedBox(width: 4),
              _buildBubble(context, time),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(BuildContext context, String time) {
    final hasAttachments = message.attachments != null && message.attachments!.isNotEmpty;

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      decoration: BoxDecoration(
        color: isMine
            ? Theme.of(context).colorScheme.primary
            : Colors.grey[200],
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: isMine
              ? const Radius.circular(16)
              : const Radius.circular(4),
          bottomRight: isMine
              ? const Radius.circular(4)
              : const Radius.circular(16),
        ),
      ),
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Вложения
            if (hasAttachments)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: message.attachments!.map((att) {
                    return AttachmentViewer(attachment: att);
                  }).toList(),
                ),
              ),
            // Текст сообщения
            if (message.content.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: hasAttachments ? 4 : 10,
                  bottom: 4,
                ),
                child: Text(
                  message.content,
                  style: TextStyle(
                    color: isMine ? Colors.white : Colors.black87,
                    fontSize: 15,
                  ),
                ),
              ),
            // Статус и время
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 11,
                      color: isMine ? Colors.white70 : Colors.grey[600],
                    ),
                  ),
                  if (isMine) ...[
                    const SizedBox(width: 4),
                    _buildStatusIcon(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    IconData icon;
    Color color;

    switch (message.status) {
      case 'READ':
        icon = Icons.done_all;
        color = Colors.blue[300]!;
        break;
      case 'DELIVERED':
        icon = Icons.done_all;
        color = Colors.white70;
        break;
      case 'SENT':
      default:
        icon = Icons.done;
        color = Colors.white70;
        break;
    }

    return Icon(icon, size: 14, color: color);
  }

  Widget _buildDeleteButton(BuildContext context) {
    if (!isAdmin) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onDelete,
      child: Container(
        margin: const EdgeInsets.only(right: 4, bottom: 6),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.delete_outline,
          size: 18,
          color: Colors.red[400],
        ),
      ),
    );
  }
}