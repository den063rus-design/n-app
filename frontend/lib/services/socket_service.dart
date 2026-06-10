import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/api_config.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;

  IO.Socket? _socket;
  Timer? _heartbeatTimer;

  SocketService._internal();

  IO.Socket? get socket => _socket;

  /// Подключается к Socket.IO серверу с JWT токеном
  void connect(String token) {
    try {
      _socket = IO.io(
        ApiConfig.socketUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': token})
            .enableAutoConnect()
            .build(),
      );

      _socket!.onConnect((_) {
        print('Socket connected: ${_socket!.id}');
        startHeartbeat();
      });

      _socket!.onDisconnect((_) {
        print('Socket disconnected');
        stopHeartbeat();
      });

      _socket!.onError((error) {
        print('Socket error: $error');
      });

      _socket!.onConnectError((error) {
        print('Socket connection error: $error');
      });

      _socket!.connect();
    } catch (e) {
      print('Socket connection failed: $e');
    }
  }

  // ========== Heartbeat ==========

  /// Запускает heartbeat — отправляет 'heartbeat' каждые 30 секунд
  void startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _socket?.emit('heartbeat');
      print('Heartbeat sent');
    });
  }

  /// Останавливает heartbeat
  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // ========== Online status listeners ==========

  /// Слушает событие 'user:online'
  void onUserOnline(Function(dynamic) handler) {
    _socket?.on('user:online', (data) => handler(data));
  }

  /// Слушает событие 'user:offline'
  void onUserOffline(Function(dynamic) handler) {
    _socket?.on('user:offline', (data) => handler(data));
  }

  // ========== Message events ==========

  /// Отправляет сообщение через Socket.IO
  void sendMessage(String text, int? receiverId) {
    _socket?.emit('message:send', {
      'text': text,
      if (receiverId != null) 'receiverId': receiverId,
    });
  }

  /// Отправляет файловое сообщение через Socket.IO
  void sendFileMessage(String text, int? receiverId, List<Map<String, dynamic>> attachments) {
    _socket?.emit('message:send', {
      'text': text,
      if (receiverId != null) 'receiverId': receiverId,
      'attachments': attachments,
    });
  }

  /// Отправляет статус прочтения сообщения
  void markAsRead(int messageId) {
    _socket?.emit('message:read', {'messageId': messageId});
  }

  /// Слушает новые сообщения
  void onNewMessage(void Function(dynamic data) callback) {
    _socket?.on('message:new', callback);
  }

  /// Слушает обновления статуса сообщения (DELIVERED / READ)
  void onMessageStatus(void Function(dynamic data) callback) {
    _socket?.on('message:status', callback);
  }

  /// Слушает обновления статуса доставки (старое событие — для обратной совместимости)
  void onMessageDelivered(void Function(dynamic data) callback) {
    _socket?.on('message:delivered', callback);
  }

  /// Слушает отметки о прочтении (старое событие — для обратной совместимости)
  void onMessageRead(void Function(dynamic data) callback) {
    _socket?.on('message:read', callback);
  }

  /// Слушает удаление сообщения
  void onMessageDeleted(void Function(dynamic data) callback) {
    _socket?.on('message:deleted', callback);
  }

  // ========== Call events ==========

  /// Отправляет событие звонка (call:start, call:accept, call:reject, call:end)
  void sendCallEvent(String event, Map<String, dynamic> data) {
    _socket?.emit(event, data);
  }

  /// Отправляет сигнал WebRTC (offer, answer, ICE candidate)
  void sendCallSignal(int callId, Map<String, dynamic> data) {
    _socket?.emit('call:signal', {'callId': callId, ...data});
  }

  /// Слушает события звонков (call:incoming, call:accepted, call:signal, call:ended)
  void onCallEvent(String event, Function(dynamic) handler) {
    _socket?.on(event, (data) => handler(data));
  }

  // ========== Notification events ==========

  /// Слушает новые уведомления
  void onNotification(Function(dynamic) handler) {
    _socket?.on('notification:new', (data) => handler(data));
  }

  /// Слушает обновления количества непрочитанных уведомлений
  void onUnreadCount(Function(dynamic) handler) {
    _socket?.on('notification:unread_count', (data) => handler(data));
  }

  /// Отключается от сервера
  void disconnect() {
    try {
      stopHeartbeat();
      _socket?.disconnect();
      _socket = null;
    } catch (e) {
      print('Socket disconnect error: $e');
    }
  }
}