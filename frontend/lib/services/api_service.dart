import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
            debugPrint('[Dio] ${options.method} ${options.path} — без токена (login)');
            handler.next(options);
            return;
          }
          final token = await _storage.read(key: 'jwt_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
            debugPrint('[Dio] ${options.method} ${options.path} — токен добавлен');
          } else {
            debugPrint('[Dio] ${options.method} ${options.path} — токен отсутствует');
          }
          handler.next(options);
        },
        onError: (error, handler) {
          debugPrint('[Dio] ERROR ${error.response?.statusCode} ${error.requestOptions.path}: ${error.response?.data}');
          if (error.response?.statusCode == 401) {
            // Token expired — можно добавить логику refresh
          }
          handler.next(error);
        },
      ),
    );
  }

  Dio get dio => _dio;

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

  Future<Map<String, dynamic>> uploadFile(String filePath) async {
    final fileName = File(filePath).uri.pathSegments.last;
    debugPrint('[ApiService.uploadFile] filePath=$filePath fileName=$fileName');

    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });

      final response = await _dio.post(
        '/files/upload',
        data: formData,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
      );

      debugPrint('[ApiService.uploadFile] response status=${response.statusCode}');
      debugPrint('[ApiService.uploadFile] response data=${response.data}');

      final decoded = response.data as Map<String, dynamic>;
      final fileKey = decoded['key'] as String?;
      if (fileKey == null) {
        throw Exception('Сервер не вернул ключ файла. Ответ: $decoded');
      }
      return {
        'key': fileKey,
        'mimeType': decoded['mimeType'] as String? ?? 'application/octet-stream',
        'originalName': decoded['originalName'] as String? ?? fileKey,
        'fileSize': decoded['fileSize'] as int? ?? 0,
      };
    } on DioException catch (e) {
      debugPrint('[ApiService.uploadFile] DioException: type=${e.type} status=${e.response?.statusCode} body=${e.response?.data}');
      String errorMsg;
      if (e.response != null) {
        final statusCode = e.response!.statusCode;
        final body = e.response!.data;
        if (body is Map<String, dynamic>) {
          errorMsg = body['message'] as String? ?? body['error'] as String? ?? 'HTTP $statusCode';
        } else {
          errorMsg = 'HTTP $statusCode: $body';
        }
      } else if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.sendTimeout) {
        errorMsg = 'Таймаут соединения при загрузке файла';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMsg = 'Ошибка сети при загрузке файла: ${e.message}';
      } else {
        errorMsg = 'Ошибка загрузки файла: ${e.message}';
      }
      throw Exception('Ошибка загрузки файла: $errorMsg');
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
