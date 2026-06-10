class ApiConfig {
  // Для Android эмулятора используйте 10.0.2.2
  // Для iOS симулятора или веба используйте localhost
  static const String baseUrl = 'http://10.0.2.2:3000';
  static const String socketUrl = 'http://10.0.2.2:3000';

  // Таймауты в миллисекундах
  static const int connectTimeout = 10000;
  static const int receiveTimeout = 15000;

  // Endpoints
  static const String login = '/auth/login';
  static const String users = '/users';
  static const String chat = '/chat';
  static const String chatMy = '/chat/my';
}