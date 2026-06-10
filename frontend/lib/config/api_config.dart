class ApiConfig {
  // Для разработки (Android эмулятор)
  static const String devBaseUrl = 'http://10.0.2.2:3000';
  static const String devWsUrl = 'ws://10.0.2.2:3000';

  // Для production (реальный сервер)
  static const String prodBaseUrl = 'https://ваш-сервер.ru';
  static const String prodWsUrl = 'wss://ваш-сервер.ru';

  // Переключение между dev и prod
  // Перед сборкой release измените на true
  static const bool isProduction = false;

  static String get baseUrl => isProduction ? prodBaseUrl : devBaseUrl;
  static String get wsUrl => isProduction ? prodWsUrl : devWsUrl;

  // Таймауты в миллисекундах
  static const int connectTimeout = 10000;
  static const int receiveTimeout = 15000;

  // Endpoints
  static const String login = '/auth/login';
  static const String users = '/users';
  static const String chat = '/chat';
  static const String chatMy = '/chat/my';
}