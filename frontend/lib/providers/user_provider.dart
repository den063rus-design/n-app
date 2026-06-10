import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class UserProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final SocketService _socketService = SocketService();

  List<User> _users = [];
  List<User> _archivedUsers = [];
  bool _isLoading = false;
  String? _error;

  // Параметры поиска/сортировки/фильтрации
  String _searchQuery = '';
  String _sortBy = 'fullName'; // fullName | age | createdAt
  String _sortOrder = 'asc'; // asc | desc
  String _statusFilter = ''; // '' | ACTIVE | BLOCKED

  List<User> get users => _users;
  List<User> get archivedUsers => _archivedUsers;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  String get sortBy => _sortBy;
  String get sortOrder => _sortOrder;
  String get statusFilter => _statusFilter;

  UserProvider() {
    _setupSocketListeners();
  }

  /// Настраивает слушатели онлайн-статуса через Socket.IO
  void _setupSocketListeners() {
    _socketService.onUserOnline((data) {
      try {
        final userId = data['userId'] as int;
        final isOnline = data['isOnline'] as bool;
        _updateUserOnlineStatus(userId, isOnline);
      } catch (e) {
        print('Error processing user:online in UserProvider: $e');
      }
    });

    _socketService.onUserOffline((data) {
      try {
        final userId = data['userId'] as int;
        final isOnline = data['isOnline'] as bool;
        _updateUserOnlineStatus(userId, isOnline);
      } catch (e) {
        print('Error processing user:offline in UserProvider: $e');
      }
    });
  }

  /// Обновляет онлайн-статус пользователя в списке _users
  void _updateUserOnlineStatus(int userId, bool isOnline) {
    bool changed = false;
    for (int i = 0; i < _users.length; i++) {
      if (_users[i].id == userId) {
        _users[i] = User(
          id: _users[i].id,
          fullName: _users[i].fullName,
          age: _users[i].age,
          role: _users[i].role,
          status: _users[i].status,
          notes: _users[i].notes,
          isOnline: isOnline,
          lastSeenAt: _users[i].lastSeenAt,
          createdAt: _users[i].createdAt,
          login: _users[i].login,
        );
        changed = true;
        break;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  Future<void> loadUsers() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _users = await _apiService.getUsers(
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        sortBy: _sortBy,
        sortOrder: _sortOrder,
        status: _statusFilter.isNotEmpty ? _statusFilter : null,
      );
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadArchivedUsers() async {
    _isLoading = true;
    notifyListeners();
    try {
      _archivedUsers = await _apiService.getArchivedUsers();
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    loadUsers();
  }

  void setSortBy(String sortBy) {
    _sortBy = sortBy;
    loadUsers();
  }

  void setSortOrder(String order) {
    _sortOrder = order;
    loadUsers();
  }

  void setStatusFilter(String status) {
    _statusFilter = status;
    loadUsers();
  }
}