import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../config/api_config.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();

  User? _currentUser;
  bool _isLoading = false;
  String? _error;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;

  /// Проверяет, есть ли сохранённый токен, и загружает пользователя
  Future<void> tryAutoLogin() async {
    final isLoggedIn = await _authService.isLoggedIn();
    if (isLoggedIn) {
      try {
        final response = await _apiService.get(ApiConfig.usersEndpoint + '/me');
        _currentUser = User.fromJson(response.data as Map<String, dynamic>);
        notifyListeners();
      } catch (e) {
        await _authService.logout();
      }
    }
  }

  /// Выполняет вход
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _authService.login(username, password);

      // Загружаем информацию о пользователе
      final response = await _apiService.get(ApiConfig.usersEndpoint + '/me');
      _currentUser = User.fromJson(response.data as Map<String, dynamic>);

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