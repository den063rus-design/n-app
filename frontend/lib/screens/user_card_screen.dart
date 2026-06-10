import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../providers/chat_provider.dart';
import 'edit_user_screen.dart';
import 'chat_screen.dart';

class UserCardScreen extends StatefulWidget {
  final User user;

  const UserCardScreen({super.key, required this.user});

  @override
  State<UserCardScreen> createState() => _UserCardScreenState();
}

class _UserCardScreenState extends State<UserCardScreen> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  final _apiService = ApiService();
  late User _user;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _statusIndicator(User user) {
    if (user.isBlocked) return '🔴';
    if (user.isOnline && user.isActive) return '🟢';
    if (!user.isOnline && user.isActive) return '⚪';
    return '⚪';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'ACTIVE':
        return 'Активен';
      case 'BLOCKED':
        return 'Заблокирован';
      case 'ARCHIVED':
        return 'В архиве';
      default:
        return status;
    }
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  /// Обновляет _user.isOnline из ChatProvider (WebSocket)
  void _syncOnlineStatus() {
    final chat = context.read<ChatProvider>();
    if (chat.selectedUser != null && chat.selectedUser!.id == _user.id) {
      if (chat.selectedUser!.isOnline != _user.isOnline) {
        setState(() {
          _user = User(
            id: _user.id,
            fullName: _user.fullName,
            age: _user.age,
            role: _user.role,
            status: _user.status,
            notes: _user.notes,
            isOnline: chat.selectedUser!.isOnline,
            lastSeenAt: _user.lastSeenAt,
            createdAt: _user.createdAt,
            login: _user.login,
          );
        });
      }
    }
  }

  Future<void> _blockUser() async {
    try {
      await _apiService.blockUser(_user.id);
      setState(() {
        _user = User(
          id: _user.id,
          fullName: _user.fullName,
          age: _user.age,
          role: _user.role,
          status: 'BLOCKED',
          notes: _user.notes,
          isOnline: _user.isOnline,
          lastSeenAt: _user.lastSeenAt,
          createdAt: _user.createdAt,
          login: _user.login,
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пользователь заблокирован')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка блокировки')),
        );
      }
    }
  }

  Future<void> _unblockUser() async {
    try {
      await _apiService.unblockUser(_user.id);
      setState(() {
        _user = User(
          id: _user.id,
          fullName: _user.fullName,
          age: _user.age,
          role: _user.role,
          status: 'ACTIVE',
          notes: _user.notes,
          isOnline: _user.isOnline,
          lastSeenAt: _user.lastSeenAt,
          createdAt: _user.createdAt,
          login: _user.login,
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пользователь разблокирован')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка разблокировки')),
        );
      }
    }
  }

  Future<void> _archiveUser() async {
    try {
      await _apiService.archiveUser(_user.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пользователь отправлен в архив')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка архивации')),
        );
      }
    }
  }

  Future<void> _saveCredentials() async {
    final login = _loginController.text.trim();
    final password = _passwordController.text.trim();

    if (login.isEmpty && password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите логин или пароль для изменения')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _apiService.updateCredentials(
        _user.id,
        login: login.isNotEmpty ? login : null,
        password: password.isNotEmpty ? password : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Данные доступа сохранены')),
        );
        _loginController.clear();
        _passwordController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка сохранения данных доступа')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Синхронизируем онлайн-статус из ChatProvider (WebSocket)
    _syncOnlineStatus();

    return Scaffold(
      appBar: AppBar(
        title: Text(_user.fullName),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Информация о пользователе
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          child: Text(
                            _user.fullName.isNotEmpty
                                ? _user.fullName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _user.fullName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(_statusIndicator(_user)),
                                  const SizedBox(width: 4),
                                  Text(
                                    _statusLabel(_user.status),
                                    style: TextStyle(
                                      color: _user.isActive
                                          ? Colors.green
                                          : _user.isBlocked
                                              ? Colors.red
                                              : Colors.orange,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _buildInfoRow('Возраст', _user.age?.toString() ?? 'Не указан'),
                    const SizedBox(height: 8),
                    _buildInfoRow('Дата создания', _formatDate(_user.createdAt)),
                    if (_user.notes != null && _user.notes!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildInfoRow('Заметки', _user.notes!),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Кнопки действий
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Действия',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.edit),
                        label: const Text('Редактировать данные'),
                        onPressed: () async {
                          final result = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => EditUserScreen(user: _user),
                            ),
                          );
                          if (result == true) {
                            // Обновляем данные пользователя
                            final updated = await _apiService.getUserById(_user.id);
                            if (mounted) {
                              setState(() => _user = updated);
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.chat),
                        label: const Text('Начать чат'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(
                                userId: _user.id,
                                userName: _user.fullName,
                                isAdmin: true,
                                isOnline: _user.isOnline,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.archive),
                        label: const Text('Отправить в архив'),
                        onPressed: _archiveUser,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Блок "Доступ в систему"
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Доступ в систему',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Логин: ${_user.login ?? "Не указан"}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _loginController,
                      decoration: const InputDecoration(
                        labelText: 'Новый логин',
                        hintText: 'Оставьте пустым, чтобы не менять',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Новый пароль',
                        hintText: 'Оставьте пустым, чтобы не менять',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveCredentials,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Сохранить логин и пароль'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Примечание: если поля пустые — данные не меняются',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Блокировка',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: Icon(
                          _user.isBlocked ? Icons.lock_open : Icons.lock,
                        ),
                        label: Text(
                          _user.isBlocked ? 'Разблокировать' : 'Заблокировать',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _user.isBlocked ? Colors.green : Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _user.isBlocked ? _unblockUser : _blockUser,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(value),
        ),
      ],
    );
  }
}
