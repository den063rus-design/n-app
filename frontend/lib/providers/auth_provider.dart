import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/call_service.dart';
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

  bool _shouldPreserveCallState() {
    final callService = CallService();
    return callService.state == CallState.RINGING &&
        (callService.currentCallId != null ||
            callService.pendingIncomingCall != null);
  }

  /// РџСЂРѕРІРµСЂСЏРµС‚, РµСЃС‚СЊ Р»Рё СЃРѕС…СЂР°РЅС‘РЅРЅС‹Р№ С‚РѕРєРµРЅ, Рё Р·Р°РіСЂСѓР¶Р°РµС‚ РїСЂРѕС„РёР»СЊ
  Future<bool> checkAuth() async {
    final isLoggedIn = await _authService.isLoggedIn();
    if (isLoggedIn) {
      final token = await _authService.getToken();
      if (token != null) {
        await CallService().init();
        if (!_shouldPreserveCallState()) {
          CallService().hardReset();
        }
        _socketService.connect(token);
        await _socketService.waitUntilConnected();
        // Heartbeat Р·Р°РїСѓСЃРєР°РµС‚СЃСЏ Р°РІС‚РѕРјР°С‚РёС‡РµСЃРєРё РІ onConnect РІРЅСѓС‚СЂРё SocketService
        // Р—Р°РіСЂСѓР¶Р°РµРј РїРѕР»РЅСѓСЋ РёРЅС„РѕСЂРјР°С†РёСЋ Рѕ РїРѕР»СЊР·РѕРІР°С‚РµР»Рµ
        await getCurrentUser();
      }
    }
    return isLoggedIn;
  }

  /// Р—Р°РіСЂСѓР¶Р°РµС‚ РїСЂРѕС„РёР»СЊ С‚РµРєСѓС‰РµРіРѕ РїРѕР»СЊР·РѕРІР°С‚РµР»СЏ СЃ СЃРµСЂРІРµСЂР° (GET /users/me)
  Future<void> getCurrentUser() async {
    try {
      final user = await _apiService.getCurrentUser();
      _currentUser = user;
      notifyListeners();
    } catch (e) {
      print('Failed to load current user: $e');
    }
  }

  /// Р’С‹РїРѕР»РЅСЏРµС‚ РІС…РѕРґ
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

      // РџРѕРґРєР»СЋС‡Р°РµРј Socket.IO
      final token = data['accessToken'];
      if (token == null || token is! String) {
        throw Exception('Сервер не вернул токен доступа');
      }
      await CallService().init();
      if (!_shouldPreserveCallState()) {
        CallService().hardReset();
      }
      _socketService.connect(token);
      final connected = await _socketService.waitUntilConnected();
      if (!connected) {
        throw Exception('Не удалось подключиться к серверу звонков');
      }
      // Heartbeat Р·Р°РїСѓСЃРєР°РµС‚СЃСЏ Р°РІС‚РѕРјР°С‚РёС‡РµСЃРєРё РІ onConnect РІРЅСѓС‚СЂРё SocketService

      // РћС‚РїСЂР°РІР»СЏРµРј FCM token РЅР° backend РїРѕСЃР»Рµ СѓСЃРїРµС€РЅРѕРіРѕ РІС…РѕРґР°
      unawaited(PushService().syncTokenToBackend());

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      // РџРѕРєР°Р·С‹РІР°РµРј СЂРµР°Р»СЊРЅСѓСЋ РѕС€РёР±РєСѓ РѕС‚ СЃРµСЂРІРµСЂР° РёР»Рё СЃРµС‚Рё
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

  /// Р’С‹РїРѕР»РЅСЏРµС‚ РІС‹С…РѕРґ
  Future<void> logout() async {
    CallService().hardReset();
    await PushService().cancelIncomingCallNotification();
    _socketService.disconnect(); // stopHeartbeat РІС‹Р·С‹РІР°РµС‚СЃСЏ РІРЅСѓС‚СЂРё disconnect
    await _authService.logout();
    _currentUser = null;
    _error = null;
    notifyListeners();
  }

  /// РћС‡РёС‰Р°РµС‚ РѕС€РёР±РєСѓ
  void clearError() {
    _error = null;
    notifyListeners();
  }
}

