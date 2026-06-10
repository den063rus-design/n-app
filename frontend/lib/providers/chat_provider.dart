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
    // Новое сообщение
    _socketService.onNewMessage((data) {
      try {
        final message = Message.fromJson(data as Map<String, dynamic>);
        _addMessageIfNotDuplicate(message);
      } catch (e) {
        print('Error parsing new message: $e');
      }
    });

    _socketService.onMessageUpdated((data) {
      try {
        final updated = Message.fromJson(data as Map<String, dynamic>);
        _updateMessage(updated);
      } catch (e) {
        print('Error parsing updated message: $e');
      }
    });

    // Обновление статуса (универсальное событие)
    _socketService.onMessageStatus((data) {
      try {
        final updated = Message.fromJson(data as Map<String, dynamic>);
        _updateMessage(updated);
      } catch (e) {
        print('Error parsing message status: $e');
      }
    });

    // Статус доставки (обратная совместимость)
    _socketService.onMessageDelivered((data) {
      try {
        final updated = Message.fromJson(data as Map<String, dynamic>);
        _updateMessage(updated);
      } catch (e) {
        print('Error parsing delivered message: $e');
      }
    });

    // Статус прочтения (обратная совместимость)
    _socketService.onMessageRead((data) {
      try {
        final updated = Message.fromJson(data as Map<String, dynamic>);
        _updateMessage(updated);
      } catch (e) {
        print('Error parsing read message: $e');
      }
    });

    // Удаление сообщения
    _socketService.onMessageDeleted((data) {
      try {
        final messageId = data is Map<String, dynamic>
            ? data['messageId'] as int
            : data as int;
        _messages.removeWhere((m) => m.id == messageId);
        notifyListeners();
      } catch (e) {
        print('Error processing deleted message: $e');
      }
    });

    // ========== Online status listeners ==========

    // Пользователь стал онлайн
    _socketService.onUserOnline((data) {
      try {
        final userId = data['userId'] as int;
        final isOnline = data['isOnline'] as bool;
        _updateUserOnlineStatus(userId, isOnline);
      } catch (e) {
        print('Error processing user:online event: $e');
      }
    });

    // Пользователь стал офлайн
    _socketService.onUserOffline((data) {
      try {
        final userId = data['userId'] as int;
        final isOnline = data['isOnline'] as bool;
        _updateUserOnlineStatus(userId, isOnline);
      } catch (e) {
        print('Error processing user:offline event: $e');
      }
    });
  }

  /// Обновляет онлайн-статус пользователя в списке _users
  void _updateUserOnlineStatus(int userId, bool isOnline) {
    bool changed = false;

    // Обновляем в списке пользователей
    for (int i = 0; i < _users.length; i++) {
      if (_users[i].id == userId) {
        _users[i] = User(
          id: _users[i].id,
          fullName: _users[i].fullName,
          age: _users[i].age,
          role: _users[i].role,
          status: _users[i].status,
          notes: _users[i].notes,
          isOnline: isOnline,
          lastSeenAt: _users[i].lastSeenAt,
          createdAt: _users[i].createdAt,
          login: _users[i].login,
        );
        changed = true;
        break;
      }
    }

    // Обновляем _selectedUser если это тот же пользователь
    if (_selectedUser != null && _selectedUser!.id == userId) {
      _selectedUser = User(
        id: _selectedUser!.id,
        fullName: _selectedUser!.fullName,
        age: _selectedUser!.age,
        role: _selectedUser!.role,
        status: _selectedUser!.status,
        notes: _selectedUser!.notes,
        isOnline: isOnline,
        lastSeenAt: _selectedUser!.lastSeenAt,
        createdAt: _selectedUser!.createdAt,
        login: _selectedUser!.login,
      );
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  /// Обновляет сообщение в списке
  void _updateMessage(Message updated) {
    final index = _messages.indexWhere((m) => m.id == updated.id);
    if (index != -1) {
      _messages[index] = updated;
      notifyListeners();
    }
  }

  /// Загружает список пользователей (для админа)
  Future<void> loadUsers() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.get(ApiConfig.users);
      final list = response as List<dynamic>;
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
      final list = response as List<dynamic>;
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
      final list = response as List<dynamic>;
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

  /// Отправляет текстовое сообщение через HTTP POST /chat
  /// [receiverId] — ID получателя (null для USER, т.к. backend сам найдёт админа)
  /// [fileKeys] — список ключей загруженных файлов (упрощённый вариант)
  /// [files] — список метаданных загруженных файлов (ключ, оригинальное имя, размер, MIME-тип)
  Future<void> sendMessage(String text, int? receiverId, {List<String>? fileKeys, List<Map<String, dynamic>>? files}) async {
    if (text.trim().isEmpty && (fileKeys == null || fileKeys.isEmpty) && (files == null || files.isEmpty)) return;

    try {
      final data = <String, dynamic>{'text': text};
      if (receiverId != null) {
        data['userId'] = receiverId;
      }
      if (files != null && files.isNotEmpty) {
        data['files'] = files;
      } else if (fileKeys != null && fileKeys.isNotEmpty) {
        data['fileKeys'] = fileKeys;
      }
      await _apiService.post(
        ApiConfig.chat,
        data: data,
      );
    } catch (e) {
      _error = 'Ошибка отправки сообщения: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateMessage(int messageId, String text) async {
    try {
      final response = await _apiService.patch(
        '${ApiConfig.chat}/message/$messageId',
        data: {'text': text},
      );
      final updated = Message.fromJson(response as Map<String, dynamic>);
      _updateMessage(updated);
    } catch (e) {
      _error = 'Ошибка редактирования сообщения: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Отправляет текстовое сообщение (удобный метод)
  Future<void> sendTextMessage(int userId, String text) async {
    await sendMessage(text, userId);
  }

  /// Отправляет файловое сообщение
  Future<void> sendFileMessage(int userId, String filePath, String fileType) async {
    try {
      final result = await uploadFile(filePath);
      if (result != null) {
        final fileKey = result['key'] as String;
        final files = [
          {
            'key': fileKey,
            'originalName': result['originalName'] as String? ?? fileKey,
            'fileSize': result['fileSize'] as int? ?? 0,
            'mimeType': result['mimeType'] as String? ?? 'application/octet-stream',
          },
        ];
        await sendMessage('', userId, files: files);
      }
    } catch (e) {
      _error = 'Ошибка отправки файла: $e';
      notifyListeners();
    }
  }

  /// Отправляет голосовое сообщение
  Future<void> sendVoiceMessage(int userId, String audioPath) async {
    try {
      final result = await uploadFile(audioPath);
      if (result != null) {
        final fileKey = result['key'] as String;
        final files = [
          {
            'key': fileKey,
            'originalName': result['originalName'] as String? ?? fileKey,
            'fileSize': result['fileSize'] as int? ?? 0,
            'mimeType': result['mimeType'] as String? ?? 'audio/mp4',
          },
        ];
        await sendMessage('', userId, files: files);
      }
    } catch (e) {
      _error = 'Ошибка отправки голосового сообщения: $e';
      notifyListeners();
    }
  }

  /// Загружает файл на сервер и возвращает Map с key, mimeType, originalName, fileSize
  Future<Map<String, dynamic>?> uploadFile(String filePath) async {
    try {
      final result = await _apiService.uploadFile(filePath);
      return result;
    } catch (e) {
      _error = 'Ошибка загрузки файла: $e';
      notifyListeners();
      rethrow;
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

  /// Отмечает сообщение как прочитанное через Socket
  void markAsRead(int messageId) {
    _socketService.markAsRead(messageId);
  }

  /// Добавляет сообщение с защитой от дублей по message.id
  void _addMessageIfNotDuplicate(Message message) {
    if (_messages.any((m) => m.id == message.id)) {
      return;
    }
    _messages.add(message);
    notifyListeners();
  }

  /// Добавляет сообщение из Socket.IO в реальном времени (с защитой от дублей)
  void addMessage(Message message) {
    _addMessageIfNotDuplicate(message);
  }

  /// Очищает ошибку
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
