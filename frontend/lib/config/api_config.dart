class ApiConfig {
  // Для разработки (Android эмулятор)
  static const String devBaseUrl = 'http://10.0.2.2:3000';
  static const String devWsUrl = 'ws://10.0.2.2:3000';

  // Для production (реальный сервер)
  static const String prodBaseUrl = 'http://95.170.111.146:3000';
  static const String prodWsUrl = 'ws://95.170.111.146:3000';

  // Переключение между dev и prod
  // Перед сборкой release измените на true
  static const bool isProduction = true;

  static String get baseUrl => isProduction ? prodBaseUrl : devBaseUrl;
  static String get wsUrl => isProduction ? prodWsUrl : devWsUrl;
  static String get socketUrl => wsUrl;

  // Таймауты в миллисекундах
  static const int connectTimeout = 10000;
  static const int receiveTimeout = 15000;

  // Endpoints
  static const String login = '/auth/login';
  static const String users = '/users';
  static const String chat = '/chat';
  static const String chatMy = '/chat/my';
}

/// Feature flag для включения V2 call-flow.
/// false — используется текущая система звонков (legacy).
/// true — V2 coordinator/service управляет звонками.
const bool kUseCallV2 = true;
const bool kUseCallV2Shadow = false;
const bool kUseCallV2FinalFlow = false;
const bool kUseCallV2UiFlow = false;
