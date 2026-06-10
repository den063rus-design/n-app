import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/notification_provider.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Уведомления'),
        actions: [
          Consumer<NotificationProvider>(
            builder: (context, provider, _) {
              if (provider.unreadCount > 0) {
                return TextButton(
                  onPressed: () => provider.markAllAsRead(),
                  child: const Text('Прочитать все'),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Consumer<NotificationProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.notifications.isEmpty) {
            return const Center(child: Text('Нет уведомлений'));
          }
          return ListView.builder(
            itemCount: provider.notifications.length,
            itemBuilder: (context, index) {
              final notification = provider.notifications[index];
              return ListTile(
                leading: Icon(
                  notification.type == 'MESSAGE' ? Icons.message : Icons.call,
                  color: notification.isRead ? Colors.grey : Colors.blue,
                ),
                title: Text(
                  notification.title,
                  style: TextStyle(
                    fontWeight:
                        notification.isRead ? FontWeight.normal : FontWeight.bold,
                  ),
                ),
                subtitle: notification.body != null
                    ? Text(notification.body!)
                    : null,
                trailing: notification.isRead
                    ? null
                    : const Icon(Icons.circle, size: 10, color: Colors.blue),
                onTap: () {
                  if (!notification.isRead) {
                    provider.markAsRead(notification.id);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}