import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../config/api_config.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final SocketService _socketService = SocketService();

  List<Message> _messages = [];
  List<User> _users = [];
  User? _selectedUser;
  bool _isLoading = false;
  String? _error;

  List<Message> get messages => _messages;
  List<User> get users => _users;
  User? get selectedUser => _selectedUser;
  bool get isLoading => _isLoading;
  String? get error => _error;

  ChatProvider() {
    _setupSocketListeners();
  }

  /// Настраивает слушатели Socket.IO
  void _setupSocketListeners() {
    _socketService.onMessageReceived((data) {
      final message = Message.fromJson(data as Map<String, dynamic>);
      _messages.add(message);
      notifyListeners();
    });

    _socketService.onUsersOnline((data) {
      // Обновление списка онлайн пользователей
      notifyListeners();
    });
  }

  /// Загружает список пользователей (для админа)
  Future<void> loadUsers() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.get(ApiConfig.usersEndpoint);
      final list = response.data as List<dynamic>;
      _users = list
          .map((e) => User.fromJson(e as Map<String, dynamic>))
          .toList();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = 'Ошибка загрузки пользователей';
      notifyListeners();
    }
  }

  /// Загружает сообщения для выбранного пользователя
  Future<void> loadMessages(int userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.get(
        '${ApiConfig.messagesEndpoint}/$userId',
      );
      final list = response.data as List<dynamic>;
      _messages = list
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = 'Ошибка загрузки сообщений';
      notifyListeners();
    }
  }

  /// Выбирает пользователя для чата
  void selectUser(User user) {
    _selectedUser = user;
    _socketService.joinRoom(user.id);
    loadMessages(user.id);
  }

  /// Отправляет сообщение
  void sendMessage({
    required int senderId,
    required int receiverId,
    required String content,
  }) {
    if (content.trim().isEmpty) return;

    _socketService.sendMessage(
      senderId: senderId,
      receiverId: receiverId,
      content: content,
    );
  }

  /// Очищает ошибку
  void clearError() {
    _error = null;
    notifyListeners();
  }
}