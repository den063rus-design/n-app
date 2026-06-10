import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';
import '../config/api_config.dart';

class AuthService {
  final ApiService _apiService = ApiService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Выполняет вход и сохраняет JWT токен
  Future<Map<String, dynamic>> login(String login, String password) async {
    try {
      final rawResponse = await _apiService.post(
        ApiConfig.login,
        data: {
          'login': login,
          'password': password,
        },
      );

      debugPrint('AuthService.login: raw response type = ${rawResponse.runtimeType}');
      debugPrint('AuthService.login: raw response = $rawResponse');

      if (rawResponse is! Map<String, dynamic>) {
        throw Exception('Неожиданный тип ответа от сервера: ${rawResponse.runtimeType}');
      }

      final data = rawResponse as Map<String, dynamic>;

      if (!data.containsKey('accessToken')) {
        debugPrint('AuthService.login: ERROR - no accessToken key in response. Keys: ${data.keys}');
        throw Exception('Сервер не вернул accessToken. Ключи ответа: ${data.keys}');
      }

      final tokenValue = data['accessToken'];
      debugPrint('AuthService.login: accessToken value = $tokenValue (type: ${tokenValue.runtimeType})');

      if (tokenValue == null) {
        throw Exception('accessToken равен null. Полный ответ: $data');
      }

      final token = tokenValue as String;

      await setToken(token);

      return data;
    } catch (e) {
      debugPrint('AuthService.login: caught error: $e');
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