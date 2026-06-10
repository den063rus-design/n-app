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
    _socketService.onNewMessage((data) {
      try {
        final message = Message.fromJson(data as Map<String, dynamic>);
        _messages.add(message);
        notifyListeners();
      } catch (e) {
        print('Error parsing new message: $e');
      }
    });

    _socketService.onMessageDelivered((data) {
      try {
        final updated = Message.fromJson(data as Map<String, dynamic>);
        final index = _messages.indexWhere((m) => m.id == updated.id);
        if (index != -1) {
          _messages[index] = updated;
          notifyListeners();
        }
      } catch (e) {
        print('Error parsing delivered message: $e');
      }
    });

    _socketService.onMessageRead((data) {
      try {
        final updated = Message.fromJson(data as Map<String, dynamic>);
        final index = _messages.indexWhere((m) => m.id == updated.id);
        if (index != -1) {
          _messages[index] = updated;
          notifyListeners();
        }
      } catch (e) {
        print('Error parsing read message: $e');
      }
    });
  }

  /// Загружает список пользователей (для админа)
  Future<void> loadUsers() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.get(ApiConfig.users);
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

  /// Загружает сообщения (GET /chat/my для user, GET /chat для admin)
  Future<void> loadMessages() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.get(ApiConfig.chatMy);
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

  /// Загружает сообщения конкретного пользователя (admin) — GET /chat/user/:userId
  Future<void> loadUserMessages(int userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.get('${ApiConfig.chat}/user/$userId');
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

  /// Выбирает пользователя для чата (admin)
  void selectUser(User user) {
    _selectedUser = user;
    loadUserMessages(user.id);
  }

  /// Отправляет сообщение через HTTP POST /chat
  /// [receiverId] — ID получателя (null для USER, т.к. backend сам найдёт админа)
  Future<void> sendMessage(String text, int? receiverId) async {
    if (text.trim().isEmpty) return;

    try {
      final data = <String, dynamic>{'text': text};
      if (receiverId != null) {
        data['receiverId'] = receiverId;
      }
      await _apiService.post(
        ApiConfig.chat,
        data: data,
      );
    } catch (e) {
      _error = 'Ошибка отправки сообщения';
      notifyListeners();
    }
  }

  /// Удаляет сообщение (admin) — DELETE /chat/:id
  Future<void> deleteMessage(int messageId) async {
    try {
      await _apiService.delete('${ApiConfig.chat}/$messageId');
      _messages.removeWhere((m) => m.id == messageId);
      notifyListeners();
    } catch (e) {
      _error = 'Ошибка удаления сообщения';
      notifyListeners();
    }
  }

  /// Добавляет сообщение из Socket.IO в реальном времени
  void addMessage(Message message) {
    _messages.add(message);
    notifyListeners();
  }

  /// Очищает ошибку
  void clearError() {
    _error = null;
    notifyListeners();
  }
}