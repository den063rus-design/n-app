import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../models/message.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadUsers();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage(ChatProvider chatProvider, AuthProvider authProvider) {
    final selectedUser = chatProvider.selectedUser;
    if (selectedUser == null) return;

    chatProvider.sendMessage(
      senderId: authProvider.currentUser!.id,
      receiverId: selectedUser.id,
      content: _messageController.text,
    );
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Администратор'),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () {
              context.read<AuthProvider>().logout();
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: Row(
        children: [
          // Список пользователей
          SizedBox(
            width: 300,
            child: Consumer<ChatProvider>(
              builder: (context, chat, _) {
                if (chat.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView.builder(
                  itemCount: chat.users.length,
                  itemBuilder: (context, index) {
                    final user = chat.users[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(user.username[0].toUpperCase()),
                      ),
                      title: Text(user.username),
                      subtitle: Text(user.role),
                      selected: chat.selectedUser?.id == user.id,
                      onTap: () => chat.selectUser(user),
                    );
                  },
                );
              },
            ),
          ),
          const VerticalDivider(width: 1),
          // Чат
          Expanded(
            child: Consumer2<ChatProvider, AuthProvider>(
              builder: (context, chat, auth, _) {
                if (chat.selectedUser == null) {
                  return const Center(
                    child: Text('Выберите пользователя для чата'),
                  );
                }

                return Column(
                  children: [
                    // Заголовок чата
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.grey[100],
                      child: Row(
                        children: [
                          CircleAvatar(
                            child: Text(
                              chat.selectedUser!.username[0].toUpperCase(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Чат с ${chat.selectedUser!.username}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Сообщения
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: chat.messages.length,
                        itemBuilder: (context, index) {
                          final message = chat.messages[index];
                          final isMine =
                              message.senderId == auth.currentUser?.id;
                          return _buildMessageBubble(message, isMine);
                        },
                      ),
                    ),
                    // Поле ввода
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              decoration: const InputDecoration(
                                hintText: 'Введите сообщение...',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                              onSubmitted: (_) =>
                                  _sendMessage(chat, auth),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.send),
                            color: Theme.of(context).colorScheme.primary,
                            onPressed: () =>
                                _sendMessage(chat, auth),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message, bool isMine) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.6,
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: isMine ? Colors.white : Colors.black87,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}