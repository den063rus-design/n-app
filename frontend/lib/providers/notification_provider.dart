import 'dart:async';
import 'package:flutter/material.dart';
import '../models/notification.dart' as models;
import '../services/api_service.dart';
import '../services/socket_service.dart';

class NotificationProvider extends ChangeNotifier {
  final ApiService _apiService;
  final SocketService _socketService;

  List<models.AppNotification> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;

  List<models.AppNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;

  // Stream для показа SnackBar/Toast
  final _notificationStream = StreamController<models.AppNotification>.broadcast();
  Stream<models.AppNotification> get onNewNotification => _notificationStream.stream;

  NotificationProvider(this._apiService, this._socketService) {
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    _socketService.onNotification((notification) {
      final appNotification = models.AppNotification.fromJson(notification);
      _notifications.insert(0, appNotification);
      _unreadCount++;
      _notificationStream.add(appNotification);
      notifyListeners();
    });

    _socketService.onUnreadCount((count) {
      _unreadCount = count;
      notifyListeners();
    });
  }

  Future<void> loadNotifications({int page = 1, int limit = 20}) async {
    _isLoading = true;
    notifyListeners();
    try {
      _notifications = await _apiService.getNotifications(page: page, limit: limit);
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

  @override
  void dispose() {
    _notificationStream.close();
    super.dispose();
  }
}