import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final SocketService _socketService = SocketService();

  User? _currentUser;
  bool _isLoading = false;
  String? _error;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;

  /// Проверяет, есть ли сохранённый токен
  Future<bool> checkAuth() async {
    final isLoggedIn = await _authService.isLoggedIn();
    if (isLoggedIn) {
      final token = await _authService.getToken();
      if (token != null) {
        _socketService.connect(token);
      }
    }
    return isLoggedIn;
  }

  /// Выполняет вход
  Future<bool> login(String login, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _authService.login(login, password);

      final userData = data['user'] as Map<String, dynamic>;
      _currentUser = User.fromJson(userData);

      // Подключаем Socket.IO
      final token = data['access_token'] as String;
      _socketService.connect(token);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _error = 'Ошибка входа. Проверьте логин и пароль.';
      notifyListeners();
      return false;
    }
  }

  /// Выполняет выход
  Future<void> logout() async {
    _socketService.disconnect();
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