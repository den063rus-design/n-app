import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/api_service.dart';
import '../services/call_service.dart';
import '../services/call_ringtone_service.dart';

/// Глобальный обработчик FCM-уведомлений в фоне (когда приложение свёрнуто или убито).
/// Должен быть отдельной top-level функцией, т.к. Dart VM вызывает её вне контекста Flutter-виджетов.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM_BG] push received — messageId=${message.messageId}, type=${message.data['type']}');

  final FlutterLocalNotificationsPlugin localNotifications =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);

  await localNotifications.initialize(initSettings);

  // Формируем payload
  final payloadData = <String, String?>{
    'type': message.data['type'],
    'senderId': message.data['senderId'],
    'senderName': message.data['senderName'],
    'messageId': message.data['messageId'],
    'callId': message.data['callId'],
    'callerId': message.data['callerId'],
    'callerName': message.data['callerName'],
  };
  final payloadJson = jsonEncode(payloadData);

  if (message.data['type'] == 'call') {
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'incoming_call_channel',
      'Входящие звонки',
      channelDescription: 'Уведомления о входящих звонках',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
      ongoing: true,
      autoCancel: false,
    );

    final NotificationDetails details =
        NotificationDetails(android: androidDetails);

    await localNotifications.show(
      message.hashCode,
      message.data['callerName'] ?? 'Входящий звонок',
      'Входящий звонок...',
      details,
      payload: payloadJson,
    );
  } else {
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'default_notification_channel',
      'Основные уведомления',
      channelDescription: 'Уведомления о новых сообщениях и звонках',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    final NotificationDetails details =
        NotificationDetails(android: androidDetails);

    await localNotifications.show(
      message.hashCode,
      message.notification?.title ?? message.data['title'] ?? 'Уведомление',
      message.notification?.body ?? message.data['body'] ?? '',
      details,
      payload: payloadJson,
    );
  }
}

/// Сервис для работы с FCM push-уведомлениями.
///
/// Отвечает за:
/// - инициализацию FCM
/// - запрос разрешения на уведомления (Android 13+)
/// - получение и обновление FCM token
/// - показ локальных уведомлений в foreground
/// - обработку нажатий на уведомления (навигация)
class PushService {
  static final PushService _instance = PushService._internal();
  factory PushService() => _instance;

  PushService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  /// Стрим для обработки нажатий на уведомления (навигация)
  final _notificationTapStream =
      StreamController<Map<String, String?>>.broadcast();
  Stream<Map<String, String?>> get onNotificationTap =>
      _notificationTapStream.stream;

  bool _initialized = false;

  /// Инициализирует Firebase (если ещё нет), FCM, локальные уведомления,
  /// запрашивает разрешение, получает token.
  Future<void> init() async {
    if (_initialized) {
      debugPrint('[PUSH] Already initialized, skipping');
      return;
    }

    debugPrint('[PUSH] init() — BEGIN');

    try {
      await Firebase.initializeApp();
      debugPrint('[PUSH] Firebase.initializeApp() OK');
    } catch (e, stack) {
      debugPrint('[PUSH] 🔴 Firebase.initializeApp() failed: $e');
      debugPrint('[PUSH] 🔴 StackTrace: $stack');
      rethrow;
    }

    // Создаём Android-каналы уведомлений
    try {
      const AndroidNotificationChannel defaultChannel = AndroidNotificationChannel(
        'default_notification_channel',
        'Основные уведомления',
        description: 'Уведомления о новых сообщениях и звонках',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      const AndroidNotificationChannel callChannel = AndroidNotificationChannel(
        'incoming_call_channel',
        'Входящие звонки',
        description: 'Уведомления о входящих звонках',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(defaultChannel);
        await androidPlugin.createNotificationChannel(callChannel);
      }
    } catch (e, stack) {
      debugPrint('[PUSH] 🔴 notification channels creation failed: $e');
      debugPrint('[PUSH] 🔴 StackTrace: $stack');
      rethrow;
    }

    // Инициализация flutter_local_notifications
    try {
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );
    } catch (e, stack) {
      debugPrint('[PUSH] 🔴 localNotifications.initialize() failed: $e');
      debugPrint('[PUSH] 🔴 StackTrace: $stack');
      rethrow;
    }

    // Регистрируем background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Запрашиваем разрешение на уведомления (Android 13+)
    await _requestPermission();

    // Получаем FCM token
    await _refreshToken();

    // Слушаем обновление token
    _fcm.onTokenRefresh.listen((newToken) {
      debugPrint('[FCM] Token обновлён: $newToken');
      _fcmToken = newToken;
      _sendTokenToBackend(newToken);
    });

    // Обработка foreground-сообщений
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // getInitialMessage() — приложение открыто из killed state
    try {
      final RemoteMessage? initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('[FCM] App opened from killed state via push: type=${initialMessage.data['type']}');
        await _emitTapFromData(initialMessage.data);
      }
    } catch (e, stack) {
      debugPrint('[PUSH] 🔴 getInitialMessage() failed: $e');
      debugPrint('[PUSH] 🔴 StackTrace: $stack');
      rethrow;
    }

    // onMessageOpenedApp — приложение открыто из background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      debugPrint('[FCM] App opened from background via push: type=${message.data['type']}');
      await _emitTapFromData(message.data);
    });

    _initialized = true;
    debugPrint('[PUSH] init() — END. Token: $_fcmToken');
  }

  /// Единый guard для проверки, нужно ли игнорировать входящий call push.
  /// Возвращает true, если push нужно проигнорировать.
  /// Причина игнора пишется в лог.
  bool _shouldIgnoreCallPush() {
    final callService = CallService();
    final state = callService.state;
    final lastCallEndTimestamp = callService.lastCallEndTimestamp;

    // 1. Если уже есть активный звонок (CALLING, RINGING, IN_CALL)
    if (state != CallState.IDLE) {
      debugPrint('[PUSH] Ignoring call push — state=$state (not IDLE)');
      return true;
    }

    // 2. Если звонок завершился менее 5 секунд назад (stale push guard)
    if (lastCallEndTimestamp != null) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - lastCallEndTimestamp;
      if (elapsed < 5000) {
        debugPrint('[PUSH] Ignoring call push — stale (call ended ${elapsed}ms ago)');
        return true;
      }
    }

    return false;
  }

  /// Запрашивает разрешение на уведомления (Android 13+).
  Future<void> _requestPermission() async {
    final status = await _fcm.getNotificationSettings();
    if (status.authorizationStatus == AuthorizationStatus.notDetermined) {
      final NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');
    }
  }

  /// Получает текущий FCM token.
  Future<void> _refreshToken() async {
    try {
      _fcmToken = await _fcm.getToken();
      debugPrint('[FCM] Token получен: $_fcmToken');
    } catch (e) {
      debugPrint('[FCM] Ошибка получения token: $e');
    }
  }

  /// Отправляет FCM token на backend.
  Future<void> _sendTokenToBackend(String token) async {
    try {
      await ApiService().patch('/users/me/fcm-token', data: {
        'fcmToken': token,
      });
      debugPrint('[FCM] Token отправлен на backend');
    } catch (e) {
      debugPrint('[FCM] Ошибка отправки token на backend: $e');
    }
  }

  /// Публичный метод для отправки token (вызывается после логина).
  Future<void> sendTokenToBackend() async {
    if (_fcmToken != null) {
      await _sendTokenToBackend(_fcmToken!);
    } else {
      await _refreshToken();
      if (_fcmToken != null) {
        await _sendTokenToBackend(_fcmToken!);
      }
    }
  }

  /// Обрабатывает foreground-сообщения — показывает локальное уведомление.
  void _handleForegroundMessage(RemoteMessage message) {
    final type = message.data['type'];
    debugPrint('[FCM_FG] push received — type=$type');

    if (type == 'call') {
      // Guard: игнорируем если уже на звонке или stale push
      if (_shouldIgnoreCallPush()) return;

      // Показываем call-уведомление (без fullScreenIntent, чтобы не перебивать Flutter-route)

      // Запускаем рингтон, если он ещё не играет через socket-flow
      if (!CallRingtoneService().isIncomingPlaying) {
        debugPrint('[FCM_FG] Starting ringtone from foreground push');
        CallRingtoneService().playIncomingRingtone();
      }
    } else {
      // Для обычных сообщений — стандартное уведомление
      final String title = message.notification?.title ??
          message.data['title'] ??
          'Уведомление';
      final String body = message.notification?.body ??
          message.data['body'] ??
          '';

      _showLocalNotification(title, body, message.data);
    }
  }

  /// Показывает call-style локальное уведомление (foreground).
  /// ВАЖНО: fullScreenIntent убран для foreground, чтобы не перебивать
  /// Flutter-route IncomingCallDialog. Для background fullScreenIntent
  /// остаётся в firebaseMessagingBackgroundHandler().
  void _showCallNotification(Map<String, dynamic> data) {
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'incoming_call_channel',
      'Входящие звонки',
      channelDescription: 'Уведомления о входящих звонках',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.call,
      ongoing: true,
      autoCancel: false,
    );

    final NotificationDetails details =
        NotificationDetails(android: androidDetails);

    final payloadMap = <String, String?>{
      'type': data['type'] as String?,
      'senderId': data['senderId'] as String?,
      'senderName': data['senderName'] as String?,
      'messageId': data['messageId'] as String?,
      'callId': data['callId'] as String?,
      'callerId': data['callerId'] as String?,
      'callerName': data['callerName'] as String?,
    };
    final payloadJson = jsonEncode(payloadMap);

    _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      data['callerName'] as String? ?? 'Входящий звонок',
      'Входящий звонок...',
      details,
      payload: payloadJson,
    );
  }

  /// Показывает локальное уведомление через flutter_local_notifications.
  void _showLocalNotification(
    String title,
    String body,
    Map<String, dynamic> data,
  ) {
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'default_notification_channel',
      'Основные уведомления',
      channelDescription: 'Уведомления о новых сообщениях и звонках',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    final NotificationDetails details =
        NotificationDetails(android: androidDetails);

    final payloadMap = <String, String?>{
      'type': data['type'] as String?,
      'senderId': data['senderId'] as String?,
      'senderName': data['senderName'] as String?,
      'messageId': data['messageId'] as String?,
      'callId': data['callId'] as String?,
      'callerId': data['callerId'] as String?,
      'callerName': data['callerName'] as String?,
    };
    final payloadJson = jsonEncode(payloadMap);

    _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payloadJson,
    );
  }

  /// Обрабатывает нажатие на локальное уведомление (foreground/background).
  /// Парсит JSON из payload и отправляет в стрим.
  void _onNotificationTap(NotificationResponse response) {
    if (response.payload == null || response.payload!.isEmpty) return;

    try {
      final Map<String, dynamic> parsed =
          jsonDecode(response.payload!) as Map<String, dynamic>;
      final data = parsed.map((key, value) => MapEntry(key, value as String?));
      debugPrint('[FCM_TAP] Notification tapped — type=${data['type']}');
      _notificationTapStream.add(data);
    } catch (e) {
      debugPrint('[FCM_TAP] Ошибка парсинга payload: $e');
      _notificationTapStream.add({'type': response.payload});
    }
  }

  /// Отправляет данные из FCM data в стрим навигации.
  /// Для type='call' также немедленно восстанавливает состояние CallService
  /// через hydrateIncomingCallFromPush, чтобы состояние RINGING было
  /// установлено даже если подписка на стрим ещё не активна
  /// (например, при getInitialMessage() до runApp()).
  Future<void> _emitTapFromData(Map<String, dynamic> data) async {
    final type = data['type'] as String?;
    if (type == null) return;

    // Для call-уведомлений — hydrate через CallService
    if (type == 'call') {
      // Guard: игнорируем если уже на звонке или stale push
      if (_shouldIgnoreCallPush()) return;

      final callId = data['callId'] as String?;
      final callerId = data['callerId'] as String?;
      final callerName = data['callerName'] as String?;
      if (callId != null && callerId != null && callerName != null) {
        debugPrint('[FCM_TAP] Hydrate from push — callId=$callId, callerId=$callerId');
        CallService().hydrateIncomingCallFromPush(
          callId: callId,
          callerId: callerId,
          callerName: callerName,
        );
      } else {
        debugPrint('[FCM_TAP] Missing fields for hydrate: callId=$callId, callerId=$callerId, callerName=$callerName');
        return;
      }
    }

    // Небольшая задержка, чтобы hydrate гарантированно применился
    // до того, как стрим будет обработан подписчиком
    await Future.delayed(const Duration(milliseconds: 50));

    _notificationTapStream.add({
      'type': type,
      'messageId': data['messageId'] as String?,
      'senderId': data['senderId'] as String?,
      'senderName': data['senderName'] as String?,
      'callId': data['callId'] as String?,
      'callerId': data['callerId'] as String?,
      'callerName': data['callerName'] as String?,
    });
  }

  /// Освобождает ресурсы.
  void dispose() {
    _notificationTapStream.close();
  }
}
