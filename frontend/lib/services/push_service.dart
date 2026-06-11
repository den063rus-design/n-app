import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/api_service.dart';

/// Р вЂњР В»Р С•Р В±Р В°Р В»РЎРЉР Р…РЎвЂ№Р в„– Р С•Р В±РЎР‚Р В°Р В±Р С•РЎвЂљРЎвЂЎР С‘Р С” Р Т‘Р В»РЎРЏ РЎвЂћР С•Р Р…Р С•Р Р†РЎвЂ№РЎвЂ¦ FCM-РЎРѓР С•Р С•Р В±РЎвЂ°Р ВµР Р…Р С‘Р в„–.
/// Р вЂќР С•Р В»Р В¶Р ВµР Р… Р В±РЎвЂ№РЎвЂљРЎРЉ Р С•Р С—РЎР‚Р ВµР Т‘Р ВµР В»РЎвЂР Р… Р Р…Р В° РЎС“РЎР‚Р С•Р Р†Р Р…Р Вµ РЎвЂљР С•Р С—Р В° (Р Р†Р Р…Р Вµ Р С”Р В»Р В°РЎРѓРЎРѓР В°), РЎвЂЎРЎвЂљР С•Р В±РЎвЂ№ Dart VM
/// Р СР С•Р С–Р В»Р В° Р ВµР С–Р С• Р Р†РЎвЂ№Р В·Р Р†Р В°РЎвЂљРЎРЉ, Р Т‘Р В°Р В¶Р Вµ Р ВµРЎРѓР В»Р С‘ Р С—РЎР‚Р С‘Р В»Р С•Р В¶Р ВµР Р…Р С‘Р Вµ Р Р† РЎвЂћР С•Р Р…Р Вµ.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM Background] Р СџР С•Р В»РЎС“РЎвЂЎР ВµР Р…Р С• РЎРѓР С•Р С•Р В±РЎвЂ°Р ВµР Р…Р С‘Р Вµ: ${message.messageId}');
  debugPrint('[FCM Background] Data: ${message.data}');

  final FlutterLocalNotificationsPlugin localNotifications =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);

  await localNotifications.initialize(initSettings);

  final AndroidNotificationDetails androidDetails =
      AndroidNotificationDetails(
    'default_notification_channel',
    'Р С›РЎРѓР Р…Р С•Р Р†Р Р…РЎвЂ№Р Вµ РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘РЎРЏ',
    channelDescription: 'Р Р€Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘РЎРЏ Р С• Р Р…Р С•Р Р†РЎвЂ№РЎвЂ¦ РЎРѓР С•Р С•Р В±РЎвЂ°Р ВµР Р…Р С‘РЎРЏРЎвЂ¦ Р С‘ Р В·Р Р†Р С•Р Р…Р С”Р В°РЎвЂ¦',
    importance: Importance.high,
    priority: Priority.high,
    showWhen: true,
    enableVibration: true,
    playSound: true,
  );

  final NotificationDetails details =
      NotificationDetails(android: androidDetails);

  // Р РЋР ВµРЎР‚Р С‘Р В°Р В»Р С‘Р В·РЎС“Р ВµР С Р Р†РЎРѓР Вµ Р Т‘Р В°Р Р…Р Р…РЎвЂ№Р Вµ Р Р† payload, РЎвЂЎРЎвЂљР С•Р В±РЎвЂ№ Р С—РЎР‚Р С‘ РЎвЂљР В°Р С—Р Вµ Р С—Р С•Р В»РЎС“РЎвЂЎР С‘РЎвЂљРЎРЉ Р С—Р С•Р В»Р Р…РЎС“РЎР‹ Р С‘Р Р…РЎвЂћР С•РЎР‚Р СР В°РЎвЂ Р С‘РЎР‹
  final payloadData = <String, String?>{};
  payloadData['type'] = message.data['type'];
  payloadData['senderId'] = message.data['senderId'];
  payloadData['senderName'] = message.data['senderName'];
  payloadData['messageId'] = message.data['messageId'];
  payloadData['callId'] = message.data['callId'];
  payloadData['callerId'] = message.data['callerId'];
  payloadData['callerName'] = message.data['callerName'];
  final payloadJson = jsonEncode(payloadData);

  await localNotifications.show(
    message.hashCode,
    message.notification?.title ?? message.data['title'] ?? 'Р Р€Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘Р Вµ',
    message.notification?.body ?? message.data['body'] ?? '',
    details,
    payload: payloadJson,
  );
}

/// Р РЋР ВµРЎР‚Р Р†Р С‘РЎРѓ Р Т‘Р В»РЎРЏ РЎР‚Р В°Р В±Р С•РЎвЂљРЎвЂ№ РЎРѓ FCM push-РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘РЎРЏР СР С‘.
///
/// Р С›РЎвЂљР Р†Р ВµРЎвЂЎР В°Р ВµРЎвЂљ Р В·Р В°:
/// - Р С‘Р Р…Р С‘РЎвЂ Р С‘Р В°Р В»Р С‘Р В·Р В°РЎвЂ Р С‘РЎР‹ FCM
/// - Р В·Р В°Р С—РЎР‚Р С•РЎРѓ РЎР‚Р В°Р В·РЎР‚Р ВµРЎв‚¬Р ВµР Р…Р С‘РЎРЏ Р Р…Р В° РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘РЎРЏ (Android 13+)
/// - Р С—Р С•Р В»РЎС“РЎвЂЎР ВµР Р…Р С‘Р Вµ Р С‘ Р С•Р В±Р Р…Р С•Р Р†Р В»Р ВµР Р…Р С‘Р Вµ FCM token
/// - Р С—Р С•Р С”Р В°Р В· Р В»Р С•Р С”Р В°Р В»РЎРЉР Р…РЎвЂ№РЎвЂ¦ РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘Р в„– Р Р† foreground
/// - Р С•Р В±РЎР‚Р В°Р В±Р С•РЎвЂљР С”РЎС“ Р Р…Р В°Р В¶Р В°РЎвЂљР С‘Р в„– Р Р…Р В° РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘РЎРЏ (Р Р…Р В°Р Р†Р С‘Р С–Р В°РЎвЂ Р С‘РЎРЏ)
class PushService {
  static final PushService _instance = PushService._internal();
  factory PushService() => _instance;

  PushService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  /// Р РЋРЎвЂљРЎР‚Р С‘Р С Р Т‘Р В»РЎРЏ Р С•Р В±РЎР‚Р В°Р В±Р С•РЎвЂљР С”Р С‘ Р Р…Р В°Р В¶Р В°РЎвЂљР С‘Р в„– Р Р…Р В° РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘РЎРЏ (Р Р…Р В°Р Р†Р С‘Р С–Р В°РЎвЂ Р С‘РЎРЏ)
  final _notificationTapStream =
      StreamController<Map<String, String?>>.broadcast();
  Stream<Map<String, String?>> get onNotificationTap =>
      _notificationTapStream.stream;

  bool _initialized = false;

  /// Р ВР Р…Р С‘РЎвЂ Р С‘Р В°Р В»Р С‘Р В·Р С‘РЎР‚РЎС“Р ВµРЎвЂљ Firebase (Р ВµРЎРѓР В»Р С‘ Р ВµРЎвЂ°РЎвЂ Р Р…Р Вµ), FCM, Р В»Р С•Р С”Р В°Р В»РЎРЉР Р…РЎвЂ№Р Вµ РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘РЎРЏ,
  /// Р В·Р В°Р С—РЎР‚Р В°РЎв‚¬Р С‘Р Р†Р В°Р ВµРЎвЂљ РЎР‚Р В°Р В·РЎР‚Р ВµРЎв‚¬Р ВµР Р…Р С‘Р Вµ, Р С—Р С•Р В»РЎС“РЎвЂЎР В°Р ВµРЎвЂљ token.
  Future<void> init() async {
    if (_initialized) return;

    await Firebase.initializeApp();

    // Р СњР В°РЎРѓРЎвЂљРЎР‚Р С•Р в„–Р С”Р В° Android-Р С”Р В°Р Р…Р В°Р В»Р В° РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘Р в„–
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'default_notification_channel',
      'Р С›РЎРѓР Р…Р С•Р Р†Р Р…РЎвЂ№Р Вµ РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘РЎРЏ',
      description: 'Р Р€Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘РЎРЏ Р С• Р Р…Р С•Р Р†РЎвЂ№РЎвЂ¦ РЎРѓР С•Р С•Р В±РЎвЂ°Р ВµР Р…Р С‘РЎРЏРЎвЂ¦ Р С‘ Р В·Р Р†Р С•Р Р…Р С”Р В°РЎвЂ¦',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(channel);
    }

    // Р ВР Р…Р С‘РЎвЂ Р С‘Р В°Р В»Р С‘Р В·Р В°РЎвЂ Р С‘РЎРЏ flutter_local_notifications
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

    // Р В Р ВµР С–Р С‘РЎРѓРЎвЂљРЎР‚Р С‘РЎР‚РЎС“Р ВµР С background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Р вЂ”Р В°Р С—РЎР‚Р В°РЎв‚¬Р С‘Р Р†Р В°Р ВµР С РЎР‚Р В°Р В·РЎР‚Р ВµРЎв‚¬Р ВµР Р…Р С‘Р Вµ Р Р…Р В° РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘РЎРЏ (Android 13+)
    await _requestPermission();

    // Р СџР С•Р В»РЎС“РЎвЂЎР В°Р ВµР С FCM token
    await _refreshToken();

    // Р РЋР В»РЎС“РЎв‚¬Р В°Р ВµР С Р С•Р В±Р Р…Р С•Р Р†Р В»Р ВµР Р…Р С‘Р Вµ token
    _fcm.onTokenRefresh.listen((newToken) {
      debugPrint('[FCM] Token Р С•Р В±Р Р…Р С•Р Р†Р В»РЎвЂР Р…: $newToken');
      _fcmToken = newToken;
      _sendTokenToBackend(newToken);
    });

    // Р С›Р В±РЎР‚Р В°Р В±Р С•РЎвЂљР С”Р В° foreground-РЎРѓР С•Р С•Р В±РЎвЂ°Р ВµР Р…Р С‘Р в„–
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Р С›Р В±РЎР‚Р В°Р В±Р С•РЎвЂљР С”Р В° Р Р…Р В°Р В¶Р В°РЎвЂљР С‘РЎРЏ Р Р…Р В° РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘Р Вµ, Р С”Р С•Р С–Р Т‘Р В° Р С—РЎР‚Р С‘Р В»Р С•Р В¶Р ВµР Р…Р С‘Р Вµ Р В±РЎвЂ№Р В»Р С• Р В·Р В°Р С”РЎР‚РЎвЂ№РЎвЂљР С•
    // Р С‘ Р С•РЎвЂљР С”РЎР‚РЎвЂ№РЎвЂљР С• Р С—Р С• РЎвЂљР В°Р С—РЎС“ Р Р…Р В° РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘Р Вµ (app terminated)
    final RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[FCM] Р СџРЎР‚Р С‘Р В»Р С•Р В¶Р ВµР Р…Р С‘Р Вµ Р С•РЎвЂљР С”РЎР‚РЎвЂ№РЎвЂљР С• РЎРѓ РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘РЎРЏ (terminated): ${initialMessage.data}');
      _emitTapFromData(initialMessage.data);
    }

    // Р С›Р В±РЎР‚Р В°Р В±Р С•РЎвЂљР С”Р В°, Р С”Р С•Р С–Р Т‘Р В° Р С—РЎР‚Р С‘Р В»Р С•Р В¶Р ВµР Р…Р С‘Р Вµ Р В±РЎвЂ№Р В»Р С• Р Р† РЎвЂћР С•Р Р…Р Вµ Р С‘ Р С—Р С•Р В»РЎРЉР В·Р С•Р Р†Р В°РЎвЂљР ВµР В»РЎРЉ РЎвЂљР В°Р С—Р Р…РЎС“Р В» РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘Р Вµ
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM] Р СџРЎР‚Р С‘Р В»Р С•Р В¶Р ВµР Р…Р С‘Р Вµ Р С•РЎвЂљР С”РЎР‚РЎвЂ№РЎвЂљР С• Р С‘Р В· РЎвЂћР С•Р Р…Р В° Р С—Р С• РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘РЎР‹: ${message.data}');
      _emitTapFromData(message.data);
    });

    _initialized = true;
    debugPrint('[FCM] PushService Р С‘Р Р…Р С‘РЎвЂ Р С‘Р В°Р В»Р С‘Р В·Р С‘РЎР‚Р С•Р Р†Р В°Р Р…. Token: $_fcmToken');
  }

  /// Р вЂ”Р В°Р С—РЎР‚Р В°РЎв‚¬Р С‘Р Р†Р В°Р ВµРЎвЂљ РЎР‚Р В°Р В·РЎР‚Р ВµРЎв‚¬Р ВµР Р…Р С‘Р Вµ Р Р…Р В° РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘РЎРЏ (Android 13+).
  Future<void> _requestPermission() async {
    final NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('[FCM] Р РЋРЎвЂљР В°РЎвЂљРЎС“РЎРѓ РЎР‚Р В°Р В·РЎР‚Р ВµРЎв‚¬Р ВµР Р…Р С‘РЎРЏ: ${settings.authorizationStatus}');
  }

  /// Р СџР С•Р В»РЎС“РЎвЂЎР В°Р ВµРЎвЂљ РЎвЂљР ВµР С”РЎС“РЎвЂ°Р С‘Р в„– FCM token.
  Future<void> _refreshToken() async {
    try {
      _fcmToken = await _fcm.getToken();
      debugPrint('[FCM] Р СџР С•Р В»РЎС“РЎвЂЎР ВµР Р… token: $_fcmToken');
    } catch (e) {
      debugPrint('[FCM] Р С›РЎв‚¬Р С‘Р В±Р С”Р В° Р С—Р С•Р В»РЎС“РЎвЂЎР ВµР Р…Р С‘РЎРЏ token: $e');
    }
  }

  /// Р С›РЎвЂљР С—РЎР‚Р В°Р Р†Р В»РЎРЏР ВµРЎвЂљ FCM token Р Р…Р В° backend.
  Future<void> _sendTokenToBackend(String token) async {
    try {
      await ApiService().patch('/users/me/fcm-token', data: {
        'fcmToken': token,
      });
      debugPrint('[FCM] Token Р С•РЎвЂљР С—РЎР‚Р В°Р Р†Р В»Р ВµР Р… Р Р…Р В° backend');
    } catch (e) {
      debugPrint('[FCM] Р С›РЎв‚¬Р С‘Р В±Р С”Р В° Р С•РЎвЂљР С—РЎР‚Р В°Р Р†Р С”Р С‘ token Р Р…Р В° backend: $e');
    }
  }

  /// Р СџРЎС“Р В±Р В»Р С‘РЎвЂЎР Р…РЎвЂ№Р в„– Р СР ВµРЎвЂљР С•Р Т‘ Р Т‘Р В»РЎРЏ Р С•РЎвЂљР С—РЎР‚Р В°Р Р†Р С”Р С‘ token (Р Р†РЎвЂ№Р В·РЎвЂ№Р Р†Р В°Р ВµРЎвЂљРЎРѓРЎРЏ Р С—Р С•РЎРѓР В»Р Вµ Р В»Р С•Р С–Р С‘Р Р…Р В°).
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

  /// Р С›Р В±РЎР‚Р В°Р В±Р В°РЎвЂљРЎвЂ№Р Р†Р В°Р ВµРЎвЂљ foreground-РЎРѓР С•Р С•Р В±РЎвЂ°Р ВµР Р…Р С‘РЎРЏ РІР‚вЂќ Р С—Р С•Р С”Р В°Р В·РЎвЂ№Р Р†Р В°Р ВµРЎвЂљ Р В»Р С•Р С”Р В°Р В»РЎРЉР Р…Р С•Р Вµ РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘Р Вµ.
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[FCM Foreground] Р СџР С•Р В»РЎС“РЎвЂЎР ВµР Р…Р С• РЎРѓР С•Р С•Р В±РЎвЂ°Р ВµР Р…Р С‘Р Вµ: ${message.messageId}');
    debugPrint('[FCM Foreground] Data: ${message.data}');

    final String title = message.notification?.title ??
        message.data['title'] ??
        'Р Р€Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘Р Вµ';
    final String body = message.notification?.body ??
        message.data['body'] ??
        '';

    _showLocalNotification(title, body, message.data);
  }

  /// Р СџР С•Р С”Р В°Р В·РЎвЂ№Р Р†Р В°Р ВµРЎвЂљ Р В»Р С•Р С”Р В°Р В»РЎРЉР Р…Р С•Р Вµ РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘Р Вµ РЎвЂЎР ВµРЎР‚Р ВµР В· flutter_local_notifications.
  /// Р вЂ™ payload Р С—Р ВµРЎР‚Р ВµР Т‘Р В°РЎвЂРЎвЂљРЎРѓРЎРЏ JSON РЎРѓР С• Р Р†РЎРѓР ВµР СР С‘ Р С—Р С•Р В»РЎРЏР СР С‘ Р Т‘Р В°Р Р…Р Р…РЎвЂ№РЎвЂ¦.
  void _showLocalNotification(
    String title,
    String body,
    Map<String, dynamic> data,
  ) {
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'default_notification_channel',
      'Р С›РЎРѓР Р…Р С•Р Р†Р Р…РЎвЂ№Р Вµ РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘РЎРЏ',
      channelDescription: 'Р Р€Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘РЎРЏ Р С• Р Р…Р С•Р Р†РЎвЂ№РЎвЂ¦ РЎРѓР С•Р С•Р В±РЎвЂ°Р ВµР Р…Р С‘РЎРЏРЎвЂ¦ Р С‘ Р В·Р Р†Р С•Р Р…Р С”Р В°РЎвЂ¦',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    final NotificationDetails details =
        NotificationDetails(android: androidDetails);

    // Р РЋР ВµРЎР‚Р С‘Р В°Р В»Р С‘Р В·РЎС“Р ВµР С Р Р†РЎРѓР Вµ Р С—Р С•Р В»РЎРЏ Р Р† JSON-РЎРѓРЎвЂљРЎР‚Р С•Р С”РЎС“ Р Т‘Р В»РЎРЏ payload
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

  /// Р С›Р В±РЎР‚Р В°Р В±Р В°РЎвЂљРЎвЂ№Р Р†Р В°Р ВµРЎвЂљ Р Р…Р В°Р В¶Р В°РЎвЂљР С‘Р Вµ Р Р…Р В° Р В»Р С•Р С”Р В°Р В»РЎРЉР Р…Р С•Р Вµ РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘Р Вµ (foreground/background).
  /// Р СџР В°РЎР‚РЎРѓР С‘РЎвЂљ JSON Р С‘Р В· payload Р С‘ Р С•РЎвЂљР С—РЎР‚Р В°Р Р†Р В»РЎРЏР ВµРЎвЂљ Р Р† РЎРѓРЎвЂљРЎР‚Р С‘Р С.
  void _onNotificationTap(NotificationResponse response) {
    debugPrint('[FCM] Р СћР В°Р С— Р С—Р С• РЎС“Р Р†Р ВµР Т‘Р С•Р СР В»Р ВµР Р…Р С‘РЎР‹: payload=${response.payload}');

    if (response.payload == null || response.payload!.isEmpty) return;

    try {
      final Map<String, dynamic> parsed =
          jsonDecode(response.payload!) as Map<String, dynamic>;
      final data = parsed.map((key, value) => MapEntry(key, value as String?));
      _notificationTapStream.add(data);
    } catch (e) {
      debugPrint('[FCM] Р С›РЎв‚¬Р С‘Р В±Р С”Р В° Р С—Р В°РЎР‚РЎРѓР С‘Р Р…Р С–Р В° payload: $e');
      // fallback РІР‚вЂќ Р ВµРЎРѓР В»Р С‘ payload РЎРЊРЎвЂљР С• Р С—РЎР‚Р С•РЎРѓРЎвЂљР С• type
      _notificationTapStream.add({'type': response.payload});
    }
  }

  /// Р С›РЎвЂљР С—РЎР‚Р В°Р Р†Р В»РЎРЏР ВµРЎвЂљ Р Т‘Р В°Р Р…Р Р…РЎвЂ№Р Вµ Р С‘Р В· FCM data Р Р† РЎРѓРЎвЂљРЎР‚Р С‘Р С Р Р…Р В°Р Р†Р С‘Р С–Р В°РЎвЂ Р С‘Р С‘.
  void _emitTapFromData(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == null) return;

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

  /// Р С›РЎРѓР Р†Р С•Р В±Р С•Р В¶Р Т‘Р В°Р ВµРЎвЂљ РЎР‚Р ВµРЎРѓРЎС“РЎР‚РЎРѓРЎвЂ№.
  void dispose() {
    _notificationTapStream.close();
  }
}