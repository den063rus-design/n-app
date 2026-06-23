import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';
import 'attachment_viewer.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isAdmin;
  final bool isMine;
  final bool isHighlighted;
  final VoidCallback? onDelete;
  final Future<void> Function(String newText)? onEdit;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isAdmin,
    required this.isMine,
    this.isHighlighted = false,
    this.onDelete,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(DateTime.parse(message.createdAt));

    // Системное сообщение о звонке — рендерим как центрированную строку, не как bubble
    if (message.isCallMessage) {
      return _buildCallSystemMessage(context, time);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onLongPress: () => _showActions(context),
                onSecondaryTapDown: (_) => _showActions(context),
                child: _buildBubble(context, time),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Рендерит системное сообщение о звонке в виде центрированной строки.
  /// Текст и иконка строятся по metadata.status + isMine (сторона bubble).
  /// callerId/calleeId из metadata читаются для будущего использования,
  /// но направление пока определяется через isMine.
  Widget _buildCallSystemMessage(BuildContext context, String time) {
    final meta = message.metadata;
    final callStatus = meta?['status'] as String? ?? 'ended';
    final durationSec = meta?['durationSec'] as int? ?? 0;
    // Читаем для будущего использования, пока не применяем для направления
    final callerId = meta?['callerId'] as int?;
    final calleeId = meta?['calleeId'] as int?;

    // Направление определяется через сторону bubble (isMine)
    final bool isOutgoing = isMine;

    // Иконка и цвет
    final bool isMissed = callStatus == 'missed';
    final IconData icon = isMissed ? Icons.phone_missed : Icons.phone_in_talk;
    final Color? iconColor = isMissed ? Colors.red[400] : Colors.grey[600];

    // Текст строится по metadata + isOutgoing
    final String displayText = _buildCallDisplayText(callStatus, durationSec, isOutgoing);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Text(
                displayText,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                time,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Строит отображаемый текст звонка по статусу, длительности и направлению.
  /// [isOutgoing] — true для исходящего звонка, false для входящего.
  String _buildCallDisplayText(String callStatus, int durationSec, bool isOutgoing) {
    switch (callStatus) {
      case 'missed':
        return isOutgoing ? 'Звонок не принят' : 'Пропущенный звонок';
      case 'rejected':
        return 'Звонок отклонён';
      case 'cancelled':
        return 'Звонок отменён';
      case 'ended':
      default:
        final prefix = isOutgoing ? 'Исходящий звонок' : 'Входящий звонок';
        if (durationSec > 0) {
          final min = durationSec ~/ 60;
          final sec = durationSec % 60;
          final durStr = '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
          return '$prefix • $durStr';
        }
        return prefix;
    }
  }

  Widget _buildBubble(BuildContext context, String time) {
    final hasAttachments = message.attachments != null && message.attachments!.isNotEmpty;

    final bgColor = isHighlighted
        ? (isMine ? Colors.amber.shade300 : Colors.amber.shade100)
        : (isMine ? Theme.of(context).colorScheme.primary : Colors.grey[200]);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: isMine ? const Radius.circular(16) : const Radius.circular(4),
          bottomRight: isMine ? const Radius.circular(4) : const Radius.circular(16),
        ),
      ),
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasAttachments)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: message.attachments!.map((attachment) {
                    return AttachmentViewer(attachment: attachment);
                  }).toList(),
                ),
              ),
            if (message.content.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: hasAttachments ? 4 : 10,
                  bottom: 4,
                ),
                child: SelectableText(
                  message.content,
                  style: TextStyle(
                    color: isMine ? Colors.white : Colors.black87,
                    fontSize: 15,
                  ),
                ),
              ),
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

  Future<void> _showActions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Копировать'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final textToCopy = message.content.trim().isEmpty
                    ? 'Сообщение без текста'
                    : message.content;
                await Clipboard.setData(ClipboardData(text: textToCopy));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Сообщение скопировано')),
                  );
                }
              },
            ),
            if (isMine && onEdit != null)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Редактировать'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final updatedText = await _showEditDialog(context);
                  if (updatedText != null && updatedText.trim().isNotEmpty) {
                    try {
                      await onEdit!(updatedText.trim());
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Не удалось сохранить: $error')),
                        );
                      }
                    }
                  }
                },
              ),
            if (isAdmin && onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Удалить', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onDelete?.call();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showEditDialog(BuildContext context) async {
    final controller = TextEditingController(text: message.content);

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Редактировать сообщение'),
        content: TextField(
          controller: controller,
          maxLines: null,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    controller.dispose();
    return result;
  }
}
