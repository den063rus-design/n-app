import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/user.dart';
import '../models/notification.dart';
import '../models/call.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(milliseconds: ApiConfig.connectTimeout),
        receiveTimeout: const Duration(milliseconds: ApiConfig.receiveTimeout),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Не добавляем токен для запроса логина
          if (options.path.contains('/auth/login')) {
            handler.next(options);
            return;
          }
          final token = await _storage.read(key: 'jwt_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          if (error.response?.statusCode == 401) {
            // Token expired — можно добавить логику refresh
          }
          handler.next(error);
        },
      ),
    );
  }

  Dio get dio => _dio;

  String get _baseUrl => ApiConfig.baseUrl;

  Future<Map<String, String>> get _headers async {
    final token = await _storage.read(key: 'jwt_token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // =================================================================
  // Базовые HTTP-методы
  // =================================================================

  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) async {
    final response = await _dio.get(path, queryParameters: queryParameters);
    return response.data;
  }

  Future<dynamic> post(String path, {dynamic data}) async {
    final response = await _dio.post(path, data: data);
    return response.data;
  }

  Future<dynamic> put(String path, {dynamic data}) async {
    final response = await _dio.put(path, data: data);
    return response.data;
  }

  Future<dynamic> patch(String path, {dynamic data}) async {
    final response = await _dio.patch(path, data: data);
    return response.data;
  }

  Future<dynamic> delete(String path) async {
    final response = await _dio.delete(path);
    return response.data;
  }

  // =================================================================
  // Users
  // =================================================================

  Future<List<User>> getUsers({
    String? search,
    String? sortBy,
    String? sortOrder,
    String? status,
  }) async {
    final params = <String, String>{};
    if (search != null) params['search'] = search;
    if (sortBy != null) params['sortBy'] = sortBy;
    if (sortOrder != null) params['sortOrder'] = sortOrder;
    if (status != null) params['status'] = status;

    final queryString = params.isNotEmpty
        ? '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}'
        : '';
    final response = await get('/users$queryString');
    return (response as List).map((u) => User.fromJson(u as Map<String, dynamic>)).toList();
  }

  Future<User> getUserById(int id) async {
    final response = await get('/users/$id');
    return User.fromJson(response as Map<String, dynamic>);
  }

  /// Получить текущего пользователя по JWT-токену (GET /users/me)
  Future<User> getCurrentUser() async {
    final response = await get('/users/me');
    return User.fromJson(response as Map<String, dynamic>);
  }

  Future<User> updateUser(int id, Map<String, dynamic> data) async {
    final response = await patch('/users/$id', data: data);
    return User.fromJson(response as Map<String, dynamic>);
  }

  Future<void> blockUser(int id) async {
    await patch('/users/$id/block', data: {});
  }

  Future<void> unblockUser(int id) async {
    await patch('/users/$id/unblock', data: {});
  }

  Future<void> archiveUser(int id) async {
    await patch('/users/$id/archive', data: {});
  }

  Future<void> restoreUser(int id) async {
    await patch('/users/$id/restore', data: {});
  }

  Future<void> deleteUser(int id) async {
    await delete('/users/$id');
  }

  Future<List<User>> getArchivedUsers() async {
    final response = await get('/users/archive');
    return (response as List).map((u) => User.fromJson(u as Map<String, dynamic>)).toList();
  }

  Future<User> createUser(Map<String, dynamic> data) async {
    final response = await post('/users', data: data);
    return User.fromJson(response as Map<String, dynamic>);
  }

  Future<void> updateCredentials(int id, {String? login, String? password}) async {
    final data = <String, String>{};
    if (login != null) data['login'] = login;
    if (password != null) data['password'] = password;
    await patch('/users/$id/credentials', data: data);
  }

  // =================================================================
  // Files
  // =================================================================

  Future<String> uploadFile(String filePath) async {
    final uri = Uri.parse('$_baseUrl/files/upload');
    final request = http.MultipartRequest('POST', uri);
    final headers = await _headers;
    headers.remove('Content-Type');
    request.headers.addAll(headers);
    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    try {
      final response = await request.send().timeout(const Duration(seconds: 30));
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode != 201 && response.statusCode != 200) {
        String errorMsg;
        try {
          final errorDecoded = jsonDecode(responseBody) as Map<String, dynamic>;
          errorMsg = errorDecoded['message'] as String? ?? errorDecoded['error'] as String? ?? 'HTTP ${response.statusCode}';
        } catch (_) {
          errorMsg = 'HTTP ${response.statusCode}: $responseBody';
        }
        throw Exception('Ошибка загрузки файла: $errorMsg');
      }
      
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final fileKey = decoded['key'] as String?;
      if (fileKey == null) {
        throw Exception('Сервер не вернул ключ файла. Ответ: $responseBody');
      }
      return fileKey;
    } on http.ClientException catch (e) {
      throw Exception('Ошибка сети при загрузке файла: ${e.message}');
    } catch (e) {
      rethrow;
    }
  }

  // =================================================================
  // Notifications
  // =================================================================

  Future<List<AppNotification>> getNotifications({int page = 1, int limit = 20}) async {
    final response = await get('/notifications/my?page=$page&limit=$limit');
    return (response as List)
        .map((n) => AppNotification.fromJson(n as Map<String, dynamic>))
        .toList();
  }

  Future<void> markNotificationRead(int id) async {
    await patch('/notifications/$id/read', data: {});
  }

  Future<void> markAllNotificationsRead() async {
    await patch('/notifications/read-all', data: {});
  }

  Future<int> getUnreadCount() async {
    final response = await get('/notifications/unread-count');
    return (response as Map<String, dynamic>)['count'] as int;
  }

  // =================================================================
  // Calls
  // =================================================================

  Future<List<Call>> getMyCalls() async {
    final response = await get('/call/my');
    return (response as List)
        .map((c) => Call.fromJson(c as Map<String, dynamic>))
        .toList();
  }
}
