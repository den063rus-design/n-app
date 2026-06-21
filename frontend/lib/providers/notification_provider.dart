import 'dart:async';

import 'package:flutter/material.dart';

import '../models/notification.dart' as models;
import '../services/api_service.dart';
import '../services/push_service.dart';
import '../services/socket_service.dart';

class NotificationProvider extends ChangeNotifier {
  final ApiService _apiService;
  final SocketService _socketService;

  final List<models.AppNotification> _notifications = [];
  final Set<String> _shownSocketMessageNotificationIds = <String>{};
  int _unreadCount = 0;
  bool _isLoading = false;

  List<models.AppNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;

  final _notificationStream =
      StreamController<models.AppNotification>.broadcast();
  Stream<models.AppNotification> get onNewNotification =>
      _notificationStream.stream;

  NotificationProvider(this._apiService, this._socketService) {
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    _socketService.onNotification((notification) {
      try {
        if (notification is Map<String, dynamic>) {
          _showLocalFallbackIfNeeded(notification);
        }

        final appNotification = models.AppNotification.fromJson(notification);
        _notifications.insert(0, appNotification);
        _unreadCount++;
        _notificationStream.add(appNotification);
        notifyListeners();
      } catch (e) {
        print('[NOTIFICATION_PROVIDER] Error processing notification:new - $e');
      }
    });

    _socketService.onUnreadCount((data) {
      try {
        print(
          '[NOTIFICATION_PROVIDER] onUnreadCount received - data type: ${data.runtimeType}, value: $data',
        );
        if (data is int) {
          _unreadCount = data;
        } else if (data is Map) {
          _unreadCount = (data['count'] as num?)?.toInt() ?? 0;
        } else {
          print(
            '[NOTIFICATION_PROVIDER] onUnreadCount - unexpected type: ${data.runtimeType}',
          );
        }
        notifyListeners();
      } catch (e) {
        print('[NOTIFICATION_PROVIDER] Error processing notification:unread_count - $e');
      }
    });
  }

  Future<void> loadNotifications({int page = 1, int limit = 20}) async {
    _isLoading = true;
    notifyListeners();
    try {
      _notifications.clear();
      _notifications.addAll(
        await _apiService.getNotifications(page: page, limit: limit),
      );
    } catch (e) {
      // ignore
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadUnreadCount() async {
    try {
      _unreadCount = await _apiService.getUnreadCount();
      notifyListeners();
    } catch (e) {
      // ignore
    }
  }

  Future<void> markAsRead(int id) async {
    try {
      await _apiService.markNotificationRead(id);
      final index = _notifications.indexWhere((n) => n.id == id);
      if (index != -1) {
        _notifications[index] = models.AppNotification(
          id: _notifications[index].id,
          userId: _notifications[index].userId,
          type: _notifications[index].type,
          title: _notifications[index].title,
          body: _notifications[index].body,
          isRead: true,
          createdAt: _notifications[index].createdAt,
        );
        _unreadCount = _unreadCount > 0 ? _unreadCount - 1 : 0;
        notifyListeners();
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> markAllAsRead() async {
    try {
      await _apiService.markAllNotificationsRead();
      _unreadCount = 0;
      notifyListeners();
    } catch (e) {
      // ignore
    }
  }

  void _showLocalFallbackIfNeeded(Map<String, dynamic> notification) {
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    final isBackgrounded = lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.detached ||
        lifecycleState == AppLifecycleState.hidden;

    if (!isBackgrounded) {
      return;
    }

    if (PushService().fcmToken != null) {
      return;
    }

    final type = (notification['type'] as String? ?? '').toUpperCase();
    if (type != 'MESSAGE') {
      return;
    }

    final rawData = notification['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : const <String, dynamic>{};

    final messageId = data['messageId']?.toString();
    final senderId = data['senderId']?.toString();
    final senderName = data['senderName']?.toString().trim();
    final rawTitle = notification['title']?.toString().trim() ?? '';
    final rawBody = notification['body']?.toString().trim() ?? '';

    final dedupeKey = messageId?.isNotEmpty == true
        ? 'message:$messageId'
        : senderId?.isNotEmpty == true
            ? 'sender:$senderId:${rawBody.hashCode}'
            : 'title:$rawTitle:${rawBody.hashCode}';

    if (_shownSocketMessageNotificationIds.contains(dedupeKey)) {
      return;
    }
    _shownSocketMessageNotificationIds.add(dedupeKey);

    final title = senderName?.isNotEmpty == true
        ? senderName!
        : rawTitle.isNotEmpty
            ? rawTitle
            : 'Новое сообщение';

    final body = rawBody.isNotEmpty
        ? rawBody
        : senderName?.isNotEmpty == true
            ? 'Новое сообщение'
            : '';

    if (title.isEmpty || body.isEmpty) {
      return;
    }

    unawaited(
      PushService().showMessageNotificationFromSocket(
        title: title,
        body: body,
        senderId: senderId,
        senderName: senderName,
        messageId: messageId,
      ),
    );
  }

  @override
  void dispose() {
    _notificationStream.close();
    super.dispose();
  }
}
