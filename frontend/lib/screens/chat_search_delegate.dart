import 'package:flutter/material.dart';
import '../models/message.dart';

/// SearchDelegate для поиска по сообщениям чата.
/// Возвращает [int] — id найденного сообщения.
class ChatSearchDelegate extends SearchDelegate<int?> {
  final List<Message> messages;

  ChatSearchDelegate({required this.messages})
      : super(
          searchFieldLabel: 'Поиск по чату...',
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
        );

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults(context);

  Widget _buildSearchResults(BuildContext context) {
    if (query.isEmpty) {
      return const Center(
        child: Text(
          'Введите текст для поиска',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    final lowerQuery = query.toLowerCase();
    final results = messages.where((msg) {
      // Поиск по тексту сообщения
      if (msg.content.toLowerCase().contains(lowerQuery)) return true;
      // Поиск по имени файла во вложениях
      if (msg.attachments != null) {
        for (final att in msg.attachments!) {
          if (att.fileName.toLowerCase().contains(lowerQuery)) return true;
        }
      }
      return false;
    }).toList();

    if (results.isEmpty) {
      return const Center(
        child: Text(
          'Ничего не найдено',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final msg = results[index];
        final hasAttachments =
            msg.attachments != null && msg.attachments!.isNotEmpty;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(
              hasAttachments ? Icons.attach_file : Icons.message,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
          ),
          title: Text(
            msg.content.isNotEmpty ? msg.content : '(файл)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14),
          ),
          subtitle: hasAttachments
              ? Text(
                  msg.attachments!.map((a) => a.fileName).join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                )
              : null,
          trailing: Text(
            _formatTime(msg.createdAt),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          onTap: () => close(context, msg.id),
        );
      },
    );
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}