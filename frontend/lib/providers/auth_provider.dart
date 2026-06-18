import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/push_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final SocketService _socketService = SocketService();

  User? _currentUser;
  bool _isLoading = false;
  String? _error;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;

  /// Проверяет, есть ли сохранённый токен, и загружает профиль
  Future<bool> checkAuth() async {
    final isLoggedIn = await _authService.isLoggedIn();
    if (isLoggedIn) {
      final token = await _authService.getToken();
      if (token != null) {
        _socketService.connect(token);
        // Heartbeat запускается автоматически в onConnect внутри SocketService
        // Загружаем полную информацию о пользователе
        await getCurrentUser();
      }
    }
    return isLoggedIn;
  }

  /// Загружает профиль текущего пользователя с сервера (GET /users/me)
  Future<void> getCurrentUser() async {
    try {
      final user = await _apiService.getCurrentUser();
      _currentUser = user;
      notifyListeners();
    } catch (e) {
      print('Failed to load current user: $e');
    }
  }

  /// Выполняет вход
  Future<bool> login(String login, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _authService.login(login, password);

      final userData = data['user'];
      if (userData is! Map<String, dynamic>) {
        throw Exception('Сервер не вернул данные пользователя');
      }
      _currentUser = User.fromJson(userData);

      // Подключаем Socket.IO
      final token = data['accessToken'];
      if (token == null || token is! String) {
        throw Exception('Сервер не вернул токен доступа');
      }
      _socketService.connect(token);
      // Heartbeat запускается автоматически в onConnect внутри SocketService

      // Отправляем FCM token на backend после успешного входа
      unawaited(PushService().syncTokenToBackend());

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      // Показываем реальную ошибку от сервера или сети
      final errorMsg = e.toString();
      if (errorMsg.contains('Unauthorized') || errorMsg.contains('401')) {
        _error = 'Неверный логин или пароль';
      } else if (errorMsg.contains('SocketException') || errorMsg.contains('Connection refused') || errorMsg.contains('connectTimeout')) {
        _error = 'Нет соединения с сервером. Проверьте подключение к интернету.';
      } else if (errorMsg.contains('HandshakeException') || errorMsg.contains('XMLHttpRequest')) {
        _error = 'Ошибка соединения. Возможно, сервер недоступен.';
      } else {
        _error = 'Ошибка: ${errorMsg.length > 100 ? errorMsg.substring(0, 100) : errorMsg}';
      }
      notifyListeners();
      return false;
    }
  }

  /// Выполняет выход
  Future<void> logout() async {
    _socketService.disconnect(); // stopHeartbeat вызывается внутри disconnect
    await _authService.logout();
    _currentUser = null;
    _error = null;
    notifyListeners();
  }

  /// Очищает ошибку
  void clearError() {
    _error = null;
    notifyListeners();
  }
}