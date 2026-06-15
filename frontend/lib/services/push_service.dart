import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/api_service.dart';
import '../services/call_ringtone_service.dart';
import '../services/call_service.dart';

/// Глобальный обработчик FCM-уведомлений в фоне
/// (когда приложение свёрнуто или убито).
///
/// Должен быть отдельной top-level функцией,
/// так как Dart VM вызывает её вне контекста Flutter-виджетов.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint(
    '[FCM_BG] push received — messageId=${message.messageId}, type=${message.data['type']}, callId=${message.data['callId']}, callerId=${message.data['callerId']}, callerName=${message.data['callerName']}',
  );

  final FlutterLocalNotificationsPlugin localNotifications =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);

  await localNotifications.initialize(initSettings);

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
    debugPrint(
      '[FCM_BG] Showing call notification — callerName=${message.data['callerName']}, callId=${message.data['callId']}',
    );

    const AndroidNotificationDetails androidDetails =
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

    const NotificationDetails details =
        NotificationDetails(android: androidDetails);

    await localNotifications.show(
      message.hashCode,
      message.data['callerName'] ?? 'Входящий звонок',
      'Входящий звонок...',
      details,
      payload: payloadJson,
    );
  } else {
    debugPrint(
      '[FCM_BG] Showing default notification — title=${message.notification?.title ?? message.data['title']}',
    );

    const AndroidNotificationDetails androidDetails =
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

    const NotificationDetails details =
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
/// - запрос разрешения на уведомления
/// - получение и обновление FCM token
/// - показ локальных уведомлений в foreground
/// - обработку нажатий на уведомления
class PushService {
  static final PushService _instance = PushService._internal();
  factory PushService() => _instance;

  PushService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  final _notificationTapStream =
      StreamController<Map<String, String?>>.broadcast();
  Stream<Map<String, String?>> get onNotificationTap =>
      _notificationTapStream.stream;

  bool _initialized = false;

  /// Инициализирует Firebase, FCM и локальные уведомления.
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

    try {
      const AndroidNotificationChannel defaultChannel =
          AndroidNotificationChannel(
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

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _requestPermission();
    await _refreshToken();

    _fcm.onTokenRefresh.listen((newToken) {
      debugPrint('[FCM] Token обновлён: $newToken');
      _fcmToken = newToken;
      _sendTokenToBackend(newToken);
    });

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    try {
      final RemoteMessage? initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        debugPrint(
          '[FCM] App opened from killed state via push: type=${initialMessage.data['type']}',
        );
        await _emitTapFromData(initialMessage.data);
      }
    } catch (e, stack) {
      debugPrint('[PUSH] 🔴 getInitialMessage() failed: $e');
      debugPrint('[PUSH] 🔴 StackTrace: $stack');
      rethrow;
    }

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      debugPrint(
        '[FCM] App opened from background via push: type=${message.data['type']}',
      );
      await _emitTapFromData(message.data);
    });

    _initialized = true;
    debugPrint('[PUSH] init() — END. Token: $_fcmToken');
  }

  /// Возвращает `true`, если входящий call push нужно проигнорировать.
  bool _shouldIgnoreCallPush() {
    final callService = CallService();
    final state = callService.state;
    final lastCallEndTimestamp = callService.lastCallEndTimestamp;

    if (state != CallState.IDLE && state != CallState.ENDED) {
      debugPrint('[PUSH] PUSH ignored because state=$state (active call in progress)');
      return true;
    }

    if (lastCallEndTimestamp != null) {
      final elapsed =
          DateTime.now().millisecondsSinceEpoch - lastCallEndTimestamp;
      if (elapsed < 5000) {
        debugPrint(
          '[PUSH] PUSH ignored because stale (call ended ${elapsed}ms ago)',
        );
        return true;
      }
    }

    return false;
  }

  /// Запрашивает разрешение на уведомления.
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

  /// Публичный метод для отправки token после логина.
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

  /// Обрабатывает foreground-сообщения.
  void _handleForegroundMessage(RemoteMessage message) {
    final type = message.data['type'];
    debugPrint(
      '[FCM_FG] push received — type=$type, callId=${message.data['callId']}, callerId=${message.data['callerId']}, callerName=${message.data['callerName']}',
    );

    if (type == 'call') {
      if (_shouldIgnoreCallPush()) return;

      final callId = message.data['callId'];
      final callerId = message.data['callerId'];
      final callerName = message.data['callerName'];

      if (callId == null || callerId == null || callerName == null) {
        debugPrint(
          '[FCM_FG] Missing call fields: callId=$callId, callerId=$callerId, callerName=$callerName',
        );
        return;
      }

      debugPrint(
        '[FCM_FG] PUSH hydrate callId=$callId, callerId=$callerId, callerName=$callerName',
      );
      CallService().hydrateIncomingCallFromPush(
        callId: callId,
        callerId: callerId,
        callerName: callerName,
      );

      Future.delayed(const Duration(milliseconds: 50), () {
        _notificationTapStream.add({
          'type': 'call',
          'callId': callId,
          'callerId': callerId,
          'callerName': callerName,
        });
      });

      if (!CallRingtoneService().isIncomingPlaying) {
        debugPrint('[FCM_FG] Starting ringtone from foreground push');
        CallRingtoneService().playIncomingRingtone();
      }

      // Fallback: если через 300ms экран входящего не открылся — показать call-уведомление
      Future.delayed(const Duration(milliseconds: 300), () {
        final cs = CallService();
        if (!cs.isIncomingDialogOpen && !cs.isCallScreenOpen && cs.state == CallState.RINGING) {
          debugPrint('[FCM_FG] ⚠️ Fallback: incoming screen not opened, showing call notification');
          _showCallNotification(message.data);
        }
      });
    } else {
      final String title = message.notification?.title ??
          message.data['title'] ??
          'Уведомление';
      final String body = message.notification?.body ??
          message.data['body'] ??
          '';

      _showLocalNotification(title, body, message.data);
    }
  }

  /// Показывает call-style локальное уведомление в foreground.
  void _showCallNotification(Map<String, dynamic> data) {
    const AndroidNotificationDetails androidDetails =
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

    const NotificationDetails details =
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

  /// Показывает обычное локальное уведомление.
  void _showLocalNotification(
    String title,
    String body,
    Map<String, dynamic> data,
  ) {
    const AndroidNotificationDetails androidDetails =
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

    const NotificationDetails details =
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

  /// Обрабатывает нажатие на локальное уведомление.
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

  /// Отправляет данные из FCM data в навигационный стрим.
  Future<void> _emitTapFromData(Map<String, dynamic> data) async {
    final type = data['type'] as String?;
    debugPrint(
      '[FCM_TAP] push tapped — type=$type, callId=${data['callId']}, callerId=${data['callerId']}, callerName=${data['callerName']}',
    );
    if (type == null) return;

    if (type == 'call') {
      if (_shouldIgnoreCallPush()) return;

      final callId = data['callId'] as String?;
      final callerId = data['callerId'] as String?;
      final callerName = data['callerName'] as String?;

      if (callId != null && callerId != null && callerName != null) {
        debugPrint(
          '[FCM_TAP] PUSH hydrate callId=$callId, callerId=$callerId, callerName=$callerName',
        );
        CallService().hydrateIncomingCallFromPush(
          callId: callId,
          callerId: callerId,
          callerName: callerName,
        );
      } else {
        debugPrint(
          '[FCM_TAP] Missing fields for hydrate: callId=$callId, callerId=$callerId, callerName=$callerName',
        );
        return;
      }
    }

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

  void dispose() {
    _notificationTapStream.close();
  }
}
