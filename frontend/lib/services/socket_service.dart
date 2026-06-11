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
    print('[SOCKET_SERVICE] 🔌 connect() called — token length: ${token.length}');
    print('[SOCKET_SERVICE] 🔌 connect() — socketUrl: ${ApiConfig.socketUrl}');
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
        print('[SOCKET_SERVICE] ✅ Socket CONNECTED: ${_socket!.id}');
        print('[SOCKET_SERVICE] ✅ Socket connected — transport: websocket');
        startHeartbeat();
      });

      _socket!.onDisconnect((_) {
        print('[SOCKET_SERVICE] 🔌 Socket DISCONNECTED');
        stopHeartbeat();
      });

      _socket!.onError((error) {
        print('[SOCKET_SERVICE] ❌ Socket error: $error');
      });

      _socket!.onConnectError((error) {
        print('[SOCKET_SERVICE] ❌ Socket connection error: $error');
      });

      _socket!.connect();
      print('[SOCKET_SERVICE] 🔌 connect() — socket.connect() called, socket.id before connect: ${_socket?.id}');
    } catch (e) {
      print('[SOCKET_SERVICE] ❌ Socket connection failed: $e');
    }
  }

  // ========== Heartbeat ==========

  /// Запускает heartbeat — отправляет 'heartbeat' каждые 30 секунд
  void startHeartbeat() {
    print('[SOCKET_SERVICE] 💓 startHeartbeat() — starting heartbeat every 30s');
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _socket?.emit('heartbeat');
      print('[SOCKET_SERVICE] 💓 Heartbeat sent');
    });
  }

  /// Останавливает heartbeat
  void stopHeartbeat() {
    print('[SOCKET_SERVICE] 💓 stopHeartbeat() — stopping heartbeat');
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

  /// Слушает обновления сообщений
  void onMessageUpdated(void Function(dynamic data) callback) {
    _socket?.on('message:updated', callback);
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
    final socketStatus = _socket != null ? 'connected (id: ${_socket!.id})' : 'NULL ⚠️';
    print('[SOCKET_SERVICE] 📤 sendCallEvent — event="$event", data=$data');
    print('[SOCKET_SERVICE] 📤 sendCallEvent — socket status: $socketStatus');
    if (_socket == null) {
      print('[SOCKET_SERVICE] ⚠️⚠️⚠️ sendCallEvent: _socket is NULL — event "$event" will NOT be sent!');
      return;
    }
    _socket!.emit(event, data);
    print('[SOCKET_SERVICE] ✅ sendCallEvent — "$event" emitted');
  }

  /// Отправляет сигнал WebRTC (offer, answer, ICE candidate)
  void sendCallSignal(int callId, Map<String, dynamic> data) {
    final socketStatus = _socket != null ? 'connected (id: ${_socket!.id})' : 'NULL ⚠️';
    print('[SOCKET_SERVICE] 📤 sendCallSignal — callId=$callId, type=${data['type']}');
    print('[SOCKET_SERVICE] 📤 sendCallSignal — full data: $data');
    print('[SOCKET_SERVICE] 📤 sendCallSignal — socket status: $socketStatus');
    if (_socket == null) {
      print('[SOCKET_SERVICE] ⚠️⚠️⚠️ sendCallSignal: _socket is NULL — signal will NOT be sent!');
      return;
    }
    _socket!.emit('call:signal', {'callId': callId, ...data});
    print('[SOCKET_SERVICE] ✅ sendCallSignal — call:signal emitted');
  }

  /// Слушает события звонков (call:incoming, call:accepted, call:signal, call:ended)
  void onCallEvent(String event, Function(dynamic) handler) {
    final socketStatus = _socket != null ? 'connected (id: ${_socket!.id})' : 'NULL ⚠️';
    print('[SOCKET_SERVICE] 👂 onCallEvent — registering listener for: "$event"');
    print('[SOCKET_SERVICE] 👂 onCallEvent — socket status: $socketStatus');
    if (_socket == null) {
      print('[SOCKET_SERVICE] ⚠️⚠️⚠️ onCallEvent: _socket is NULL — listener for "$event" will NOT be registered!');
      return;
    }
    _socket!.on(event, (data) {
      print('[SOCKET_SERVICE] 📥📥📥 EVENT RECEIVED: "$event" — data: $data');
      print('[SOCKET_SERVICE] 📥 event received — socket.id: ${_socket?.id}');
      handler(data);
    });
    print('[SOCKET_SERVICE] ✅ onCallEvent — listener for "$event" registered successfully');
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
