import 'dart:async';
import 'dart:ui' show VoidCallback;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/api_config.dart';
import 'call_logger.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;

  IO.Socket? _socket;
  Timer? _heartbeatTimer;

  // CallLogger для записи call-логов в файл на телефоне
  final CallLogger _callLogger = CallLogger();

  // Callback, который вызывается при подключении socket
  // Используется CallService для донавешивания listeners после connect
  VoidCallback? _onConnectCallback;

  // StreamController для оповещения о состоянии подключения
  // Испускает true при connect/reconnect и false при disconnect
  final _connectionController = StreamController<bool>.broadcast();

  /// Стрим, оповещающий об изменении состояния подключения socket.
  /// true — подключён, false — отключён.
  Stream<bool> get onConnectionChanged => _connectionController.stream;

  SocketService._internal();

  IO.Socket? get socket => _socket;

  /// Устанавливает callback, который будет вызван при подключении socket
  void setOnConnectCallback(VoidCallback callback) {
    _log('[SOCKET_SERVICE] setOnConnectCallback — callback set');
    _onConnectCallback = callback;
    // Если socket уже подключён — вызываем сразу
    if (_socket != null && _socket!.connected) {
      _log('[SOCKET_SERVICE] setOnConnectCallback — socket already connected, invoking callback immediately');
      callback();
    }
  }

  /// Подключается к Socket.IO серверу с JWT токеном
  void connect(String token) {
    _log('[SOCKET_SERVICE] 🔌 connect() called — token length: ${token.length}');
    _log('[SOCKET_SERVICE] 🔌 connect() — socketUrl: ${ApiConfig.socketUrl}');
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
        _log('[SOCKET_SERVICE] ✅✅✅ Socket CONNECTED: ${_socket!.id}');
        _log('[SOCKET_SERVICE] ✅ Socket connected — transport: websocket');
        startHeartbeat();

        // Оповещаем подписчиков о подключении (connect/reconnect)
        _connectionController.add(true);

        // Вызываем callback для донавешивания call-листенеров
        if (_onConnectCallback != null) {
          _log('[SOCKET_SERVICE] 🔔 Invoking onConnectCallback after connect');
          _onConnectCallback!();
        } else {
          _log('[SOCKET_SERVICE] ⚠️ onConnectCallback is NOT set — call listeners may not be registered');
        }
      });

      _socket!.onDisconnect((_) {
        _log('[SOCKET_SERVICE] 🔌 Socket DISCONNECTED');
        stopHeartbeat();
        // Оповещаем подписчиков об отключении
        _connectionController.add(false);
      });

      _socket!.onError((error) {
        _log('[SOCKET_SERVICE] ❌ Socket error: $error');
      });

      _socket!.onConnectError((error) {
        _log('[SOCKET_SERVICE] ❌ Socket connection error: $error');
      });

      _socket!.connect();
      _log('[SOCKET_SERVICE] 🔌 connect() — socket.connect() called');
    } catch (e) {
      _log('[SOCKET_SERVICE] ❌ Socket connection failed: $e');
    }
  }

  // ========== Heartbeat ==========

  /// Запускает heartbeat — отправляет 'heartbeat' каждые 30 секунд
  void startHeartbeat() {
    _log('[SOCKET_SERVICE] 💓 startHeartbeat() — starting heartbeat every 30s');
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _socket?.emit('heartbeat');
      _log('[SOCKET_SERVICE] 💓 Heartbeat sent');
    });
  }

  /// Останавливает heartbeat
  void stopHeartbeat() {
    _log('[SOCKET_SERVICE] 💓 stopHeartbeat() — stopping heartbeat');
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
    _log('[SOCKET_SERVICE] 📤 sendCallEvent — event="$event", data=$data');
    _log('[SOCKET_SERVICE] 📤 sendCallEvent — socket status: $socketStatus');
    if (_socket == null) {
      _log('[SOCKET_SERVICE] ⚠️⚠️⚠️ sendCallEvent: _socket is NULL — event "$event" will NOT be sent!');
      return;
    }
    _socket!.emit(event, data);
    _log('[SOCKET_SERVICE] ✅ sendCallEvent — "$event" emitted');
  }

  /// Отправляет сигнал WebRTC (offer, answer, ICE candidate)
  void sendCallSignal(int callId, Map<String, dynamic> data) {
    final socketStatus = _socket != null ? 'connected (id: ${_socket!.id})' : 'NULL ⚠️';
    _log('[SOCKET_SERVICE] 📤 sendCallSignal — callId=$callId, type=${data['type']}');
    _log('[SOCKET_SERVICE] 📤 sendCallSignal — full data: $data');
    _log('[SOCKET_SERVICE] 📤 sendCallSignal — socket status: $socketStatus');
    if (_socket == null) {
      _log('[SOCKET_SERVICE] ⚠️⚠️⚠️ sendCallSignal: _socket is NULL — signal will NOT be sent!');
      return;
    }
    _socket!.emit('call:signal', {'callId': callId, ...data});
    _log('[SOCKET_SERVICE] ✅ sendCallSignal — call:signal emitted');
  }

  /// Слушает события звонков (call:incoming, call:accepted, call:signal, call:ended)
  void onCallEvent(String event, Function(dynamic) handler) {
    final socketStatus = _socket != null ? 'connected (id: ${_socket!.id})' : 'NULL ⚠️';
    _log('[SOCKET_SERVICE] 👂👂👂 onCallEvent — registering listener for: "$event"');
    _log('[SOCKET_SERVICE] 👂 onCallEvent — socket status: $socketStatus');
    if (_socket == null) {
      _log('[SOCKET_SERVICE] ⚠️⚠️⚠️ onCallEvent: _socket is NULL — listener for "$event" will NOT be registered!');
      _log('[SOCKET_SERVICE] ⚠️⚠️⚠️ onCallEvent: This means _setupSocketListeners was called before socket connect');
      return;
    }
    _socket!.on(event, (data) {
      _log('[SOCKET_SERVICE] 📥📥📥📥📥 EVENT RECEIVED: "$event" — data: $data');
      _log('[SOCKET_SERVICE] 📥 event received — socket.id: ${_socket?.id}');
      handler(data);
      _log('[SOCKET_SERVICE] ✅ handler for "$event" completed');
    });
    _log('[SOCKET_SERVICE] ✅✅✅ onCallEvent — listener for "$event" registered successfully');
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
      _log('[SOCKET_SERVICE] 🔌 disconnect() called');
      stopHeartbeat();
      _socket?.disconnect();
      _socket = null;
      _log('[SOCKET_SERVICE] 🔌 disconnect() — done');
    } catch (e) {
      _log('[SOCKET_SERVICE] ❌ Socket disconnect error: $e');
    }
  }

  /// Освобождает ресурсы сервиса.
  /// Должен вызываться при завершении работы приложения.
  void dispose() {
    _log('[SOCKET_SERVICE] 🗑️ dispose() called');
    stopHeartbeat();
    _socket?.disconnect();
    _socket = null;
    _connectionController.close();
    _log('[SOCKET_SERVICE] 🗑️ dispose() — done');
  }

  /// Пишет лог одновременно в print (adb) и в файл (CallLogger)
  void _log(String message) {
    print(message);
    _callLogger.log('SocketService', message);
  }
}
