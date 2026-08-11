import 'package:flutter/foundation.dart';

class ChatNavigationService {
  ChatNavigationService._internal();

  static final ChatNavigationService _instance =
      ChatNavigationService._internal();

  factory ChatNavigationService() => _instance;

  final ValueNotifier<int?> activeChatUserId = ValueNotifier<int?>(null);

  void setActiveChat(int userId) {
    activeChatUserId.value = userId;
  }

  void clearActiveChat(int userId) {
    if (activeChatUserId.value == userId) {
      activeChatUserId.value = null;
    }
  }

  bool isChatOpenWith(int? userId) {
    return userId != null && activeChatUserId.value == userId;
  }
}
