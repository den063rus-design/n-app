import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/api_config.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;

  IO.Socket? _socket;

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
      });

      _socket!.onDisconnect((_) {
        print('Socket disconnected');
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

  /// Отправляет сообщение через Socket.IO
  void sendMessage(String text, int? receiverId) {
    _socket?.emit('message:send', {
      'text': text,
      if (receiverId != null) 'receiverId': receiverId,
    });
  }

  /// Слушает новые сообщения
  void onNewMessage(void Function(dynamic data) callback) {
    _socket?.on('message:new', callback);
  }

  /// Слушает обновления статуса сообщения
  void onMessageDelivered(void Function(dynamic data) callback) {
    _socket?.on('message:delivered', callback);
  }

  /// Слушает отметки о прочтении
  void onMessageRead(void Function(dynamic data) callback) {
    _socket?.on('message:read', callback);
  }

  /// Отключается от сервера
  void disconnect() {
    try {
      _socket?.disconnect();
      _socket = null;
    } catch (e) {
      print('Socket disconnect error: $e');
    }
  }
}