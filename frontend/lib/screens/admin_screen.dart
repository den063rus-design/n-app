import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/user_provider.dart';
import '../providers/notification_provider.dart';
import '../widgets/notification_badge.dart';
import 'user_card_screen.dart';
import 'create_user_screen.dart';
import 'archive_screen.dart';
import 'notifications_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().loadUsers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Администратор'),
        actions: [
          Consumer<NotificationProvider>(
            builder: (context, provider, _) {
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    tooltip: 'Уведомления',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NotificationsScreen(),
                        ),
                      );
                    },
                  ),
                  if (provider.unreadCount > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: NotificationBadge(count: provider.unreadCount),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: 'Выйти',
            onPressed: () {
              context.read<AuthProvider>().logout();
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: Consumer<UserProvider>(
        builder: (context, userProvider, _) {
          return Column(
            children: [
              // Поле поиска
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Поиск по ФИО...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (value) {
                    userProvider.setSearchQuery(value);
                  },
                ),
              ),
              // Row с сортировкой
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    const Text('Сортировать по:'),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: userProvider.sortBy,
                      items: const [
                        DropdownMenuItem(value: 'fullName', child: Text('ФИО')),
                        DropdownMenuItem(value: 'age', child: Text('Возрасту')),
                        DropdownMenuItem(value: 'createdAt', child: Text('Дате создания')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          userProvider.setSortBy(value);
                        }
                      },
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      icon: Icon(
                        userProvider.sortOrder == 'asc'
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                      ),
                      tooltip: userProvider.sortOrder == 'asc'
                          ? 'По возрастанию'
                          : 'По убыванию',
                      onPressed: () {
                        userProvider.setSortOrder(
                          userProvider.sortOrder == 'asc' ? 'desc' : 'asc',
                        );
                      },
                    ),
                  ],
                ),
              ),
              // Row с фильтрами
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    _buildFilterChip('Все', '', userProvider),
                    const SizedBox(width: 8),
                    _buildFilterChip('Активные', 'ACTIVE', userProvider),
                    const SizedBox(width: 8),
                    _buildFilterChip('Заблокированные', 'BLOCKED', userProvider),
                  ],
                ),
              ),
              // Кнопки действий
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.person_add),
                      label: const Text('Добавить пользователя'),
                      onPressed: () async {
                        final result = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const CreateUserScreen(),
                          ),
                        );
                        if (result == true) {
                          userProvider.loadUsers();
                        }
                      },
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.archive),
                      label: const Text('Архив'),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ArchiveScreen(),
                          ),
                        );
                        userProvider.loadUsers();
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Список пользователей
              Expanded(
                child: _buildUserList(userProvider),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, UserProvider provider) {
    final isSelected = provider.statusFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        provider.setStatusFilter(value);
      },
    );
  }

  Widget _buildUserList(UserProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Ошибка: ${provider.error}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => provider.loadUsers(),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (provider.users.isEmpty) {
      return const Center(
        child: Text('Пользователи не найдены'),
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadUsers(),
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: provider.users.length,
        itemBuilder: (context, index) {
          final user = provider.users[index];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                child: Text(user.fullName.isNotEmpty
                    ? user.fullName[0].toUpperCase()
                    : '?'),
              ),
              title: Text(
                user.fullName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Row(
                children: [
                  Text(_statusIndicator(user)),
                  const SizedBox(width: 4),
                  Text(_statusLabel(user.status)),
                  if (user.age != null) ...[
                    const SizedBox(width: 12),
                    Text('${user.age} лет'),
                  ],
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserCardScreen(user: user),
                  ),
                );
                // Обновляем список после возврата
                provider.loadUsers();
              },
            ),
          );
        },
      ),
    );
  }
}