class ApiConfig {
  // Для Android эмулятора используйте 10.0.2.2
  // Для iOS симулятора или веба используйте localhost
  static const String baseUrl = 'http://10.0.2.2:3000';
  static const String localBaseUrl = 'http://localhost:3000';

  // Таймауты в миллисекундах
  static const int connectTimeout = 10000;
  static const int receiveTimeout = 15000;

  // Endpoints
  static const String loginEndpoint = '/auth/login';
  static const String registerEndpoint = '/auth/register';
  static const String usersEndpoint = '/users';
  static const String messagesEndpoint = '/chat/messages';
  static const String conversationsEndpoint = '/chat/conversations';
}