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

    _socket!.connect();
  }

  /// Отправляет сообщение через Socket.IO
  void sendMessage(String text, int userId) {
    _socket?.emit('sendMessage', {
      'text': text,
      'userId': userId,
    });
  }

  /// Слушает новые сообщения
  void onNewMessage(void Function(dynamic data) callback) {
    _socket?.on('newMessage', callback);
  }

  /// Отключается от сервера
  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }
}