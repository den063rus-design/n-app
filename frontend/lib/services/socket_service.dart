import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/api_config.dart';
import 'auth_service.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;

  IO.Socket? _socket;
  final AuthService _authService = AuthService();

  SocketService._internal();

  IO.Socket? get socket => _socket;

  /// Подключается к Socket.IO серверу
  Future<void> connect() async {
    final token = await _authService.getToken();

    _socket = IO.io(
      ApiConfig.baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setExtraHeaders({
            'Authorization': 'Bearer $token',
          })
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

  /// Присоединяется к комнате чата
  void joinRoom(int userId) {
    _socket?.emit('join', {'userId': userId});
  }

  /// Отправляет сообщение
  void sendMessage({
    required int senderId,
    required int receiverId,
    required String content,
  }) {
    _socket?.emit('sendMessage', {
      'senderId': senderId,
      'receiverId': receiverId,
      'content': content,
    });
  }

  /// Слушает новые сообщения
  void onMessageReceived(void Function(dynamic data) callback) {
    _socket?.on('newMessage', callback);
  }

  /// Слушает список пользователей онлайн
  void onUsersOnline(void Function(dynamic data) callback) {
    _socket?.on('usersOnline', callback);
  }

  /// Отключается от сервера
  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }
}