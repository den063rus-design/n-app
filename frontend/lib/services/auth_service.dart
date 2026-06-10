import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';
import '../config/api_config.dart';

class AuthService {
  final ApiService _apiService = ApiService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Выполняет вход и сохраняет JWT токен
  Future<Map<String, dynamic>> login(String login, String password) async {
    try {
      final response = await _apiService.post(
        ApiConfig.login,
        data: {
          'login': login,
          'password': password,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final token = data['access_token'] as String;

      await setToken(token);

      return data;
    } catch (e) {
      rethrow;
    }
  }

  /// Сохраняет JWT токен в secure storage
  Future<void> setToken(String token) async {
    await _storage.write(key: 'jwt_token', value: token);
  }

  /// Получает сохранённый JWT токен
  Future<String?> getToken() async {
    return await _storage.read(key: 'jwt_token');
  }

  /// Удаляет JWT токен (выход из системы)
  Future<void> logout() async {
    await _storage.delete(key: 'jwt_token');
  }

  /// Проверяет, авторизован ли пользователь
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}