import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../models/message.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';
import '../config/api_config.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _messageController = TextEditingController();
  final _fioController = TextEditingController();
  final _ageController = TextEditingController();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final ApiService _apiService = ApiService();

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
    _fioController.dispose();
    _ageController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _sendMessage(ChatProvider chatProvider, AuthProvider authProvider) {
    final selectedUser = chatProvider.selectedUser;
    if (selectedUser == null) return;

    chatProvider.sendMessage(
      _messageController.text,
      selectedUser.id,
    );
    _messageController.clear();
  }

  Future<void> _createUser() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Создать пользователя'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _fioController,
                decoration: const InputDecoration(labelText: 'ФИО'),
              ),
              TextField(
                controller: _ageController,
                decoration: const InputDecoration(labelText: 'Возраст'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: _loginController,
                decoration: const InputDecoration(labelText: 'Логин'),
              ),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Пароль'),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _apiService.post(
                  ApiConfig.users,
                  data: {
                    'fio': _fioController.text,
                    'age': int.tryParse(_ageController.text) ?? 0,
                    'login': _loginController.text,
                    'password': _passwordController.text,
                  },
                );
                _fioController.clear();
                _ageController.clear();
                _loginController.clear();
                _passwordController.clear();
                if (ctx.mounted) Navigator.pop(ctx);
                context.read<ChatProvider>().loadUsers();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ошибка создания пользователя')),
                );
              }
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  Future<void> _blockUser(User user) async {
    try {
      await _apiService.patch('${ApiConfig.users}/${user.id}/block');
      context.read<ChatProvider>().loadUsers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка')),
      );
    }
  }

  Future<void> _unblockUser(User user) async {
    try {
      await _apiService.patch('${ApiConfig.users}/${user.id}/unblock');
      context.read<ChatProvider>().loadUsers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка')),
      );
    }
  }

  Future<void> _archiveUser(User user) async {
    try {
      await _apiService.patch('${ApiConfig.users}/${user.id}/archive');
      context.read<ChatProvider>().loadUsers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка')),
      );
    }
  }

  Future<void> _restoreUser(User user) async {
    try {
      await _apiService.patch('${ApiConfig.users}/${user.id}/restore');
      context.read<ChatProvider>().loadUsers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка')),
      );
    }
  }

  Future<void> _deleteUser(User user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить пользователя'),
        content: Text('Вы уверены, что хотите удалить ${user.fio}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _apiService.delete('${ApiConfig.users}/${user.id}');
        context.read<ChatProvider>().loadUsers();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка удаления')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Администратор'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: _createUser,
            tooltip: 'Создать пользователя',
          ),
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
                    return _buildUserCard(user, chat);
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
                              chat.selectedUser!.fio[0].toUpperCase(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Чат с ${chat.selectedUser!.fio}',
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
                          return _buildMessageBubble(message, isMine, chat);
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

  Widget _buildUserCard(User user, ChatProvider chat) {
    final isSelected = chat.selectedUser?.id == user.id;
    final statusColor = user.isActive
        ? Colors.green
        : user.isBlocked
            ? Colors.red
            : Colors.orange;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: isSelected ? Colors.blue[50] : null,
      child: ListTile(
        leading: CircleAvatar(
          child: Text(user.fio[0].toUpperCase()),
        ),
        title: Text(
          user.fio,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Возраст: ${user.age}'),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(_statusLabel(user.status)),
              ],
            ),
          ],
        ),
        selected: isSelected,
        onTap: () => chat.selectUser(user),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'block':
                _blockUser(user);
                break;
              case 'unblock':
                _unblockUser(user);
                break;
              case 'archive':
                _archiveUser(user);
                break;
              case 'restore':
                _restoreUser(user);
                break;
              case 'delete':
                _deleteUser(user);
                break;
            }
          },
          itemBuilder: (context) => [
            if (user.isActive) ...[
              const PopupMenuItem(
                value: 'block',
                child: Text('Заблокировать'),
              ),
              const PopupMenuItem(
                value: 'archive',
                child: Text('Архивировать'),
              ),
            ],
            if (user.isBlocked) ...[
              const PopupMenuItem(
                value: 'unblock',
                child: Text('Разблокировать'),
              ),
              const PopupMenuItem(
                value: 'archive',
                child: Text('Архивировать'),
              ),
            ],
            if (user.isArchived) ...[
              const PopupMenuItem(
                value: 'restore',
                child: Text('Восстановить'),
              ),
            ],
            const PopupMenuItem(
              value: 'delete',
              child: Text('Удалить', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'ACTIVE':
        return 'Активен';
      case 'BLOCKED':
        return 'Заблокирован';
      case 'ARCHIVED':
        return 'Архивирован';
      default:
        return status;
    }
  }

  Widget _buildMessageBubble(Message message, bool isMine, ChatProvider chat) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 8, right: isMine ? 36 : 0, left: isMine ? 0 : 36),
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
              maxWidth: MediaQuery.of(context).size.width * 0.5,
            ),
            child: Text(
              message.content,
              style: TextStyle(
                color: isMine ? Colors.white : Colors.black87,
                fontSize: 15,
              ),
            ),
          ),
          // Кнопка удаления сообщения (только для админа)
          if (!isMine && message.id != null)
            Positioned(
              right: 0,
              top: 0,
              child: GestureDetector(
                onTap: () => chat.deleteMessage(message.id!),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red[100],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: Colors.red[700],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}