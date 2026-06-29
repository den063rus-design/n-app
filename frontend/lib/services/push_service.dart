import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/call_ringtone_service.dart';
import '../services/call_service.dart';
import '../services/chat_navigation_service.dart';
import '../config/api_config.dart';
import '../call_v2/call_v2_service.dart';
import '../call_v2/call_v2_debug.dart';

const String _defaultNotificationChannelId = 'default_notification_channel';
const String _messageAlertsChannelId = 'message_alerts_channel';
const String _messageSummaryChannelId = 'message_summary_channel';
const String _incomingCallChannelId = 'incoming_call_channel';
const String _missedCallChannelId = 'missed_call_channel';

/// Префикс для ключа SharedPreferences, хранящего счётчик сообщений
/// для одного отправителя. Полный ключ: message_count_<senderKey>.
const String _messageCountPrefPrefix = 'message_count_';

Future<void> _ensureNotificationChannels(
  FlutterLocalNotificationsPlugin notifications,
) async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  const AndroidNotificationChannel defaultChannel = AndroidNotificationChannel(
    _defaultNotificationChannelId,
    '\u041e\u0441\u043d\u043e\u0432\u043d\u044b\u0435 \u0443\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f',
    description:
        '\u0423\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f \u043e \u043d\u043e\u0432\u044b\u0445 \u0441\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u044f\u0445 \u0438 \u0437\u0432\u043e\u043d\u043a\u0430\u0445',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  const AndroidNotificationChannel messageAlertsChannel =
      AndroidNotificationChannel(
    _messageAlertsChannelId,
    '\u0421\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u044f',
    description:
        '\u0417\u0432\u0443\u043a \u0438 \u0432\u0441\u043f\u043b\u044b\u0432\u0430\u044e\u0449\u0435\u0435 \u0443\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u0435 \u0434\u043b\u044f \u043a\u0430\u0436\u0434\u043e\u0433\u043e \u043d\u043e\u0432\u043e\u0433\u043e \u0441\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u044f',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  const AndroidNotificationChannel messageSummaryChannel =
      AndroidNotificationChannel(
    _messageSummaryChannelId,
    '\u0413\u0440\u0443\u043f\u043f\u044b \u0441\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u0439',
    description:
        '\u0422\u0438\u0445\u043e\u0435 \u0441\u0432\u043e\u0434\u043d\u043e\u0435 \u0443\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u0435 \u043f\u043e \u0434\u0438\u0430\u043b\u043e\u0433\u0443',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );

  const AndroidNotificationChannel callChannel = AndroidNotificationChannel(
    _incomingCallChannelId,
    '\u0412\u0445\u043e\u0434\u044f\u0449\u0438\u0435 \u0437\u0432\u043e\u043d\u043a\u0438',
    description:
        '\u0423\u0432\u0435\u0434\u043e\u043c\u043b\u0435\u043d\u0438\u044f \u043e \u0432\u0445\u043e\u0434\u044f\u0449\u0438\u0445 \u0437\u0432\u043e\u043d\u043a\u0430\u0445',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  final androidPlugin = notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (androidPlugin == null) {
    return;
  }

  const AndroidNotificationChannel missedCallChannel = AndroidNotificationChannel(
    _missedCallChannelId,
    'Пропущенные звонки',
    description: 'Уведомления о пропущенных звонках',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  await androidPlugin.createNotificationChannel(defaultChannel);
  await androidPlugin.createNotificationChannel(messageAlertsChannel);
  await androidPlugin.createNotificationChannel(messageSummaryChannel);
  await androidPlugin.createNotificationChannel(callChannel);
  await androidPlugin.createNotificationChannel(missedCallChannel);
}

int _messageNotificationIdForSender({
  String? senderId,
  String? title,
}) {
  final senderKey =
      (senderId?.trim().isNotEmpty == true) ? senderId!.trim() : (title ?? '');
  return PushService.messageNotificationBaseId +
      senderKey.hashCode.abs() % 99999;
}

String _messageNotificationSenderKey({
  String? senderId,
  String? title,
}) {
  return (senderId?.trim().isNotEmpty == true)
      ? senderId!.trim()
      : (title ?? '');
}

String _messageNotificationAlertTagPrefix(String senderKey) {
  return 'message_alert_$senderKey';
}

String _messageNotificationSummaryTag(String senderKey) {
  return 'message_summary_$senderKey';
}

Future<void> _cancelMessageNotificationGroup({
  required FlutterLocalNotificationsPlugin notifications,
  String? senderId,
  String? title,
  SharedPreferences? prefs,
}) async {
  final summaryId = _messageNotificationIdForSender(
    senderId: senderId,
    title: title,
  );
  final senderKey = _messageNotificationSenderKey(
    senderId: senderId,
    title: title,
  );
  final alertTagPrefix = _messageNotificationAlertTagPrefix(senderKey);
  final summaryTag = _messageNotificationSummaryTag(senderKey);

  // Сбрасываем persistent счётчик при очистке уведомления.
  if (prefs != null) {
    final prefKey = '$_messageCountPrefPrefix$senderKey';
    await prefs.remove(prefKey);
  }

  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await PushService.notificationsChannel.invokeMethod<void>(
        'cancelNotificationsByTagPrefix',
        {
          'tagPrefix': alertTagPrefix,
          'summaryId': summaryId,
          'summaryTag': summaryTag,
        },
      );
      return;
    }

    final active = await notifications.getActiveNotifications();
    for (final notification in active) {
      final notificationId = notification.id;
      if (notificationId == null) continue;
      if (notificationId == summaryId) {
        await notifications.cancel(notificationId);
      }
    }
  } catch (_) {
    try {
      await notifications.cancel(summaryId);
    } catch (_) {}
  }
}

Future<void> _showGroupedMessageNotification({
  required FlutterLocalNotificationsPlugin notifications,
  required Map<String, int> countsBySender,
  required String title,
  required String body,
  required Map<String, dynamic> data,
  SharedPreferences? prefs,
}) async {
  final senderId = data['senderId'] as String?;
  final senderKey = _messageNotificationSenderKey(
    senderId: senderId,
    title: title,
  );

  // Стабильный notificationId на одного отправителя.
  // Один sender → одна карточка, которая обновляется при новых сообщениях.
  final notificationId = _messageNotificationIdForSender(
    senderId: senderId,
    title: title,
  );

  // Счётчик сообщений от этого отправителя.
  // Приоритет: countsBySender (foreground) > SharedPreferences (background/killed).
  int prevCount;
  if (countsBySender.containsKey(senderKey)) {
    // Foreground: используем in-memory счётчик.
    prevCount = countsBySender[senderKey]!;
  } else if (prefs != null) {
    // Background/killed: читаем из SharedPreferences.
    final prefKey = '$_messageCountPrefPrefix$senderKey';
    prevCount = prefs.getInt(prefKey) ?? 0;
  } else {
    prevCount = 0;
  }

  final count = prevCount + 1;
  countsBySender[senderKey] = count;

  // Сохраняем счётчик в SharedPreferences для background/killed сценариев.
  if (prefs != null) {
    final prefKey = '$_messageCountPrefPrefix$senderKey';
    await prefs.setInt(prefKey, count);
  }

  // Body со счётчиком: для первого сообщения — просто текст,
  // для следующих — текст + счётчик.
  final displayBody = count > 1 ? '$body (+$count)' : body;

  final payloadJson = jsonEncode(<String, String?>{
    'type': data['type'] as String?,
    'senderId': data['senderId'] as String?,
    'senderName': data['senderName'] as String?,
    'messageId': data['messageId'] as String?,
    'callId': data['callId'] as String?,
    'callerId': data['callerId'] as String?,
    'callerName': data['callerName'] as String?,
  });

  // Без tag — Android обновляет существующее уведомление по notificationId.
  // Это даёт стабильную группировку без дублей.
  final androidDetails = AndroidNotificationDetails(
    _messageAlertsChannelId,
    'Основные уведомления',
    channelDescription: 'Уведомления о новых сообщениях и звонках',
    importance: Importance.max,
    priority: Priority.max,
    showWhen: true,
    enableVibration: true,
    playSound: true,
    onlyAlertOnce: false,
  );

  await notifications.show(
    notificationId,
    title,
    displayBody,
    NotificationDetails(android: androidDetails),
    payload: payloadJson,
  );
}

/// Глобальный обработчик FCM-уведомлений в фоне
/// (когда приложение свёрнуто или убито).
///
/// Должен быть отдельной top-level функцией,
/// так как Dart VM вызывает её вне контекста Flutter-виджетов.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final type = message.data['type'];
  final title = message.notification?.title ?? message.data['title'];
  final body = message.notification?.body ?? message.data['body'];

  if ((type == null || type.isEmpty) &&
      (title == null || title.isEmpty) &&
      (body == null || body.isEmpty) &&
      message.data.isEmpty) {
    debugPrint('[FCM_BG] Ignoring empty background remote message');
    return;
  }

  debugPrint(
    "[FCM_BG] push received - messageId=${message.messageId}, type=${message.data['type']}, callId=${message.data['callId']}, callerId=${message.data['callerId']}, callerName=${message.data['callerName']}",
  );

  final FlutterLocalNotificationsPlugin localNotifications =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);

  await localNotifications.initialize(initSettings);
  await _ensureNotificationChannels(localNotifications);

  // Получаем SharedPreferences для persistent счётчика сообщений.
  // В background/killed сценариях in-memory countsBySender недоступен,
  // поэтому храним счётчик в SharedPreferences.
  final SharedPreferences prefs = await SharedPreferences.getInstance();

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
  if (type == 'call_end') {
    debugPrint(
      "[FCM_BG] Cancelling call notification - callId=${message.data['callId']}",
    );
    await localNotifications.cancel(PushService.incomingCallNotificationId);
    return;
  }

  if (type == 'call') {
    Future<void> showCallNotification() async {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        _incomingCallChannelId,
        'Входящие звонки',
        channelDescription: 'Уведомления о входящих звонках',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        ongoing: false,
        autoCancel: true,
      );

      const NotificationDetails details =
          NotificationDetails(android: androidDetails);

      await localNotifications.show(
        PushService.incomingCallNotificationId,
        message.data['callerName'] ?? 'Входящий звонок',
        'Входящий звонок...',
        details,
        payload: payloadJson,
      );
    }

    debugPrint(
      "[FCM_BG] Showing call notification - callerName=${message.data['callerName']}, callId=${message.data['callId']}",
    );

    await showCallNotification();
    return;
  }

  if (type == 'missed_call') {
    final callerName = message.data['callerName'] ?? 'Пользователь';
    final callerIdStr = message.data['callerId'];
    final callIdStr = message.data['callId'];
    debugPrint(
      "[FCM_BG] Showing missed call notification - callerName=$callerName callerId=$callerIdStr callId=$callIdStr",
    );

    final callerId = callerIdStr != null ? int.tryParse(callerIdStr) : null;
    final notificationId = PushService.missedCallNotificationBaseId +
        (callerId?.hashCode.abs() ?? callerName.hashCode.abs()) % 99999;

    const androidDetails = AndroidNotificationDetails(
      _missedCallChannelId,
      'Пропущенные звонки',
      channelDescription: 'Уведомления о пропущенных звонках',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const details = NotificationDetails(android: androidDetails);

    await localNotifications.show(
      notificationId,
      callerName,
      'Пропущенный звонок',
      details,
      payload: payloadJson,
    );
    return;
  }

  final senderName = (message.data['senderName'] ?? '').trim();
  final resolvedTitleSource = (message.data['title'] ?? title ?? '').trim();
  final resolvedBodySource = (message.data['body'] ?? body ?? '').trim();
  final messageTitle = senderName.isNotEmpty
      ? senderName
      : resolvedTitleSource.isNotEmpty
          ? resolvedTitleSource
          : 'Новое сообщение';
  final messageBody =
      resolvedBodySource.isNotEmpty ? resolvedBodySource : 'Новое сообщение';
  debugPrint(
    "[FCM_BG] Showing local message notification - title=$messageTitle senderId=${message.data['senderId']}",
  );

  await _showGroupedMessageNotification(
    notifications: localNotifications,
    countsBySender: <String, int>{},
    title: messageTitle,
    body: messageBody,
    data: {
      'type': type,
      'senderId': message.data['senderId'],
      'senderName': message.data['senderName'],
      'messageId': message.data['messageId'],
      'callId': message.data['callId'],
      'callerId': message.data['callerId'],
      'callerName': message.data['callerName'],
    },
    prefs: prefs,
  );
}

class PushService {
  static final PushService _instance = PushService._internal();
  factory PushService() => _instance;

  PushService._internal();
  static const bool _v2CallUiEnabled = kUseCallV2;

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _notificationsChannel =
      MethodChannel('com.napp.app/notifications');
  static MethodChannel get notificationsChannel => _notificationsChannel;

  /// Фиксированный ID для call-уведомления (чтобы не залипало).
  static const int incomingCallNotificationId = 777001;
  static const int messageNotificationBaseId = 880000;
  static const int missedCallNotificationBaseId = 777100;

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  /// Последний успешно отправленный на backend токен.
  String? _lastSentToken;

  /// Флаг: идёт ли отправка токена (защита от дублей).
  bool _isSendingToken = false;
  final Map<String, int> _messageNotificationCountsBySender = {};

  final _notificationTapStream =
      StreamController<Map<String, String?>>.broadcast();
  Stream<Map<String, String?>> get onNotificationTap =>
      _notificationTapStream.stream;
  Map<String, String?>? _pendingMessageTapData;
  Map<String, String?>? _pendingCallTapData;

  bool _initialized = false;

  Map<String, String?>? consumePendingMessageTap() {
    final data = _pendingMessageTapData;
    _pendingMessageTapData = null;
    return data;
  }

  Map<String, String?>? consumePendingCallTap() {
    final data = _pendingCallTapData;
    _pendingCallTapData = null;
    return data;
  }

  void clearPendingMessageTap() {
    _pendingMessageTapData = null;
  }

  void clearPendingCallTap() {
    _pendingCallTapData = null;
  }

  int messageNotificationIdForSender({
    String? senderId,
    String? title,
  }) {
    final senderKey = (senderId?.trim().isNotEmpty == true)
        ? senderId!.trim()
        : (title ?? '');
    return messageNotificationBaseId + senderKey.hashCode.abs() % 99999;
  }

  Future<void> cancelMessageNotificationForSender({
    String? senderId,
    String? title,
  }) async {
    final senderKey = _messageNotificationSenderKey(
      senderId: senderId,
      title: title,
    );
    _messageNotificationCountsBySender.remove(senderKey);
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await _cancelMessageNotificationGroup(
        notifications: _localNotifications,
        senderId: senderId,
        title: title,
        prefs: prefs,
      );
    } catch (_) {}
  }

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
      await _ensureNotificationChannels(_localNotifications);
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

      final notificationLaunchDetails =
          await _localNotifications.getNotificationAppLaunchDetails();
      final launchResponse = notificationLaunchDetails?.notificationResponse;
      if (notificationLaunchDetails?.didNotificationLaunchApp == true &&
          launchResponse?.payload != null &&
          launchResponse!.payload!.isNotEmpty) {
        debugPrint('[PUSH] App launched from local notification tap');
        await _handleNotificationTap(launchResponse.payload!);
      }
    } catch (e, stack) {
      debugPrint('[PUSH] 🔴 localNotifications.initialize() failed: $e');
      debugPrint('[PUSH] 🔴 StackTrace: $stack');
      rethrow;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _requestPermission();
    await _refreshToken();

    // После init() — синхронизируем токен с backend
    await syncTokenToBackend();

    _fcm.onTokenRefresh.listen((newToken) {
      debugPrint('[FCM] Token refreshed: $newToken');
      _fcmToken = newToken;
      syncTokenToBackend();
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

  /// Единый метод синхронизации FCM токена с backend.
  ///
  /// 1. Если _isSendingToken == true → return (защита от дублей)
  /// 2. Если _fcmToken == null → _refreshToken()
  /// 3. Если после refresh token всё ещё null → лог и return
  /// 4. Если _lastSentToken == _fcmToken → лог и return (уже отправлен)
  /// 5. Иначе отправить token на backend
  /// 6. После успеха: _lastSentToken = _fcmToken
  Future<void> syncTokenToBackend() async {
    if (_isSendingToken) {
      debugPrint('[FCM] token sync skipped — already sending');
      return;
    }

    // Если токена нет — пробуем получить
    if (_fcmToken == null) {
      debugPrint('[FCM] token sync begin — _fcmToken is null, refreshing...');
      await _refreshToken();
    }

    if (_fcmToken == null) {
      debugPrint(
          '[FCM] token sync skipped — _fcmToken still null after refresh');
      return;
    }

    // Если токен уже отправлен — пропускаем
    if (_lastSentToken == _fcmToken) {
      debugPrint('[FCM] token sync skipped — same token already sent');
      return;
    }

    _isSendingToken = true;
    debugPrint('[FCM] token sync begin — sending token to backend');

    try {
      await ApiService().patch('/users/me/fcm-token', data: {
        'fcmToken': _fcmToken,
      });
      _lastSentToken = _fcmToken;
      debugPrint('[FCM] token sync success');
    } catch (e) {
      debugPrint('[FCM] token sync failed: $e');
    } finally {
      _isSendingToken = false;
    }
  }

  /// Отменяет call-уведомление (снимает залипшее уведомление из статус-бара).
  /// ?????????? `true`, ???? ???????? call push ????? ???????????????.
  bool _shouldIgnoreCallPush() {
    final callService = CallService();
    final state = callService.state;
    final lastCallEndTimestamp = callService.lastCallEndTimestamp;

    if (state != CallState.IDLE && state != CallState.ENDED) {
      debugPrint(
          '[PUSH] PUSH ignored because state=$state (active call in progress)');
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

  bool _shouldIgnoreCallTapPayload({
    required String? callId,
    required String? callerId,
    required String? callerName,
  }) {
    if (callId == null || callerId == null || callerName == null) {
      debugPrint(
        '[FCM_TAP] Ignoring call tap - missing fields callId=$callId callerId=$callerId callerName=$callerName',
      );
      return true;
    }

    final parsedCallId = int.tryParse(callId);
    if (parsedCallId == null) {
      debugPrint('[FCM_TAP] Ignoring call tap - invalid callId=$callId');
      return true;
    }

    final callService = CallService();
    if (callService.lastEndedCallId == parsedCallId) {
      debugPrint(
        '[FCM_TAP] Ignoring call tap - callId=$parsedCallId already ended locally',
      );
      return true;
    }

    if (_shouldIgnoreCallPush()) {
      debugPrint(
        '[FCM_TAP] Ignoring call tap - push guard rejected callId=$parsedCallId',
      );
      return true;
    }

    return false;
  }

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

  Future<void> _refreshToken() async {
    try {
      _fcmToken = await _fcm.getToken();
      debugPrint('[FCM] Token refreshed: $_fcmToken');
    } catch (e) {
      debugPrint('[FCM] Token refresh failed: $e');
    }
  }

  Future<void> cancelIncomingCallNotification() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _notificationsChannel.invokeMethod<void>(
          'cancelNotificationById',
          {'id': incomingCallNotificationId},
        ).timeout(const Duration(seconds: 1));
      } else {
        await _localNotifications
            .cancel(incomingCallNotificationId)
            .timeout(const Duration(seconds: 1));
      }
      debugPrint(
        '[PUSH] call notification cancelled (id=$incomingCallNotificationId)',
      );
    } on TimeoutException {
      debugPrint('[PUSH] cancelIncomingCallNotification timeout');
    } catch (e) {
      debugPrint('[PUSH] cancelIncomingCallNotification failed: $e');
    }
  }

  /// Показывает notification о пропущенном звонке.
  /// Вызывается из CallService._endCall() когда входящий звонок не был принят.
  Future<void> showMissedCallNotification({
    required String callerName,
    int? callerId,
  }) async {
    debugPrint('[PUSH] showMissedCallNotification — callerName=$callerName callerId=$callerId');

    const androidDetails = AndroidNotificationDetails(
      _missedCallChannelId,
      'Пропущенные звонки',
      channelDescription: 'Уведомления о пропущенных звонках',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const details = NotificationDetails(android: androidDetails);

    final payloadMap = <String, String?>{
      'type': 'missed_call',
      'callerId': callerId?.toString(),
      'callerName': callerName,
    };
    final payloadJson = jsonEncode(payloadMap);

    // Используем отдельный ID на основе callerId, чтобы не затирать
    // последующие пропущенные от других людей.
    final notificationId = PushService.missedCallNotificationBaseId +
        (callerId?.hashCode.abs() ?? callerName.hashCode.abs()) % 99999;

    await _localNotifications.show(
      notificationId,
      callerName,
      'Пропущенный звонок',
      details,
      payload: payloadJson,
    );
  }

  /// Обрабатывает foreground-сообщения.
  void _handleForegroundMessage(RemoteMessage message) {
    final type = message.data['type'];
    debugPrint(
      '[FCM_FG] push received - type=$type, callId=${message.data['callId']}, callerId=${message.data['callerId']}, callerName=${message.data['callerName']}',
    );

    if (type == 'call_end') {
      debugPrint('[FCM_FG] call_end received - cancelling call notification');
      unawaited(cancelIncomingCallNotification());
      unawaited(CallRingtoneService().stopAllCallSounds());
      return;
    }

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

      // V2 primary: bootstrap incoming session из foreground push.
      if (_v2CallUiEnabled) {
        final parsedCallId = int.tryParse(callId);
        final parsedCallerId = int.tryParse(callerId);
        if (parsedCallId != null && parsedCallerId != null) {
          callV2Log('PUSH', 'foreground push bootstrap callId=$parsedCallId callerId=$parsedCallerId');
          // Сначала гидратируем CallService (data bootstrap), затем V2
          CallService().hydrateIncomingCallFromPush(
            callId: callId,
            callerId: callerId,
            callerName: callerName,
          );
          CallV2Service.instance.handleIncomingFromPushTap(
            callId: parsedCallId,
            callerId: parsedCallerId,
            callerName: callerName,
          );
        }
      }

      if (!CallRingtoneService().isIncomingPlaying) {
        debugPrint('[FCM_FG] Starting ringtone from foreground push');
        CallRingtoneService().playIncomingRingtone();
      }

      Future.delayed(const Duration(milliseconds: 300), () {
        final cs = CallService();
        if (!cs.isIncomingDialogOpen &&
            !cs.isCallScreenOpen &&
            cs.state == CallState.RINGING) {
          debugPrint(
              '[FCM_FG] Fallback: incoming screen not opened, showing call notification');
          _showCallNotification(message.data);
        }
      });

      return;
    }

    if (type == 'missed_call') {
      final callerName = message.data['callerName'] ?? 'Пользователь';
      final callIdStr = message.data['callId'];
      debugPrint(
        '[FCM_FG] missed_call received — showing missed-call notification (callerName=$callerName callId=$callIdStr)',
      );
      unawaited(showMissedCallNotification(
        callerName: callerName,
        callerId: int.tryParse(message.data['callerId'] ?? ''),
      ));
      return;
    }

    final senderId = int.tryParse(message.data['senderId'] ?? '');
    if (ChatNavigationService().isChatOpenWith(senderId)) {
      debugPrint(
        '[FCM_FG] Skipping message notification because matching chat is already open',
      );
      return;
    }

    final senderName = (message.data['senderName'] ?? '').trim();
    final rawTitle =
        (message.notification?.title ?? message.data['title'] ?? '').trim();
    final title = senderName.isNotEmpty
        ? senderName
        : rawTitle.isNotEmpty
            ? rawTitle
            : '\u041d\u043e\u0432\u043e\u0435 \u0441\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u0435';
    final body = message.notification?.body ?? message.data['body'] ?? '';

    _showLocalNotification(title, body, message.data);
  }

  /// Показывает call-style локальное уведомление в foreground.
  Future<void> showIncomingCallNotificationFromSocket({
    required String callId,
    required String callerId,
    required String callerName,
  }) async {
    debugPrint(
        '[PUSH] showIncomingCallNotificationFromSocket ? callId=$callId callerId=$callerId callerName=$callerName');
    _showCallNotification({
      'type': 'call',
      'callId': callId,
      'callerId': callerId,
      'callerName': callerName,
    });

    if (!CallRingtoneService().isIncomingPlaying) {
      await CallRingtoneService().playIncomingRingtone();
    }
  }

  Future<void> showMessageNotificationFromSocket({
    required String title,
    required String body,
    String? senderId,
    String? senderName,
    String? messageId,
  }) async {
    final normalizedSenderName = senderName?.trim() ?? '';
    final rawTitle = title.trim();
    final normalizedTitle = normalizedSenderName.isNotEmpty
        ? normalizedSenderName
        : rawTitle.isNotEmpty
            ? rawTitle
            : '\u041d\u043e\u0432\u043e\u0435 \u0441\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u0435';
    final normalizedBody = body.trim().isEmpty
        ? '\u041d\u043e\u0432\u043e\u0435 \u0441\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u0435'
        : body.trim();

    _showLocalNotification(normalizedTitle, normalizedBody, {
      'type': 'message',
      'senderId': senderId,
      'senderName': senderName,
      'messageId': messageId,
    });
  }

  void _showCallNotification(Map<String, dynamic> data) {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _incomingCallChannelId,
      'Входящие звонки',
      channelDescription: 'Уведомления о входящих звонках',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.call,
      ongoing: false,
      autoCancel: true,
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
      PushService.incomingCallNotificationId,
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
    final type = data['type'] as String?;
    if (type == 'message') {
      unawaited(
        _showGroupedMessageNotification(
          notifications: _localNotifications,
          countsBySender: _messageNotificationCountsBySender,
          title: title,
          body: body,
          data: data,
        ),
      );
      return;
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _defaultNotificationChannelId,
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

    final notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _localNotifications.show(
      notificationId,
      title,
      body,
      details,
      payload: payloadJson,
    );
  }

  /// Обрабатывает нажатие на локальное уведомление.
  void _onNotificationTap(NotificationResponse response) {
    if (response.payload == null || response.payload!.isEmpty) return;

    unawaited(_handleNotificationTap(response.payload!));
  }

  Future<void> _handleNotificationTap(String payload) async {
    try {
      final Map<String, dynamic> parsed =
          jsonDecode(payload) as Map<String, dynamic>;
      debugPrint('[FCM_TAP] Notification tapped ??? type=${parsed['type']}');
      await _emitTapFromData(parsed);
    } catch (e) {
      debugPrint('[FCM_TAP] Failed to decode notification payload: $e');
      _notificationTapStream.add({'type': payload});
    }
  }

  Future<void> _emitTapFromData(Map<String, dynamic> data) async {
    final type = data['type'] as String?;
    debugPrint(
      '[FCM_TAP] push tapped — type=$type, callId=${data['callId']}, callerId=${data['callerId']}, callerName=${data['callerName']}',
    );
    if (type == null) return;
    await cancelIncomingCallNotification();

    // При тапе на message-уведомление сбрасываем persistent счётчик.
    if (type == 'message') {
      try {
        final senderId = data['senderId'] as String?;
        final senderName = data['senderName'] as String?;
        final senderKey = _messageNotificationSenderKey(
          senderId: senderId,
          title: senderName,
        );
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final prefKey = '$_messageCountPrefPrefix$senderKey';
        await prefs.remove(prefKey);
        _messageNotificationCountsBySender.remove(senderKey);
        debugPrint(
          '[FCM_TAP] Reset message counter for senderKey=$senderKey',
        );
      } catch (_) {}
    }

    if (type == 'call') {
      final callId = data['callId'] as String?;
      final callerId = data['callerId'] as String?;
      final callerName = data['callerName'] as String?;

      _pendingCallTapData = {
        'type': 'call',
        'callId': callId,
        'callerId': callerId,
        'callerName': callerName,
      };

      if (_shouldIgnoreCallTapPayload(
        callId: callId,
        callerId: callerId,
        callerName: callerName,
      )) {
        _pendingCallTapData = null;
        return;
      }

      // V2 primary: bootstrap incoming session из push tap.
      if (_v2CallUiEnabled) {
        final parsedCallId = int.tryParse(callId ?? '');
        final parsedCallerId = int.tryParse(callerId ?? '');
        if (parsedCallId != null && parsedCallerId != null) {
          callV2Log('PUSH', 'tap bootstrap callId=$parsedCallId callerId=$parsedCallerId');
          // Сначала гидратируем CallService (data bootstrap), затем V2
          CallService().hydrateIncomingCallFromPush(
            callId: callId!,
            callerId: callerId!,
            callerName: callerName!,
          );
          CallV2Service.instance.handleIncomingFromPushTap(
            callId: parsedCallId,
            callerId: parsedCallerId,
            callerName: callerName,
          );
        }
        _pendingCallTapData = null;
        return;
      }

    }

    // Для call-типов при V2 не эмитим в стрим — V2 сам управляет навигацией
    await Future.delayed(const Duration(milliseconds: 50));

    final payload = {
      'type': type,
      'messageId': data['messageId'] as String?,
      'senderId': data['senderId'] as String?,
      'senderName': data['senderName'] as String?,
      'callId': data['callId'] as String?,
      'callerId': data['callerId'] as String?,
      'callerName': data['callerName'] as String?,
    };

    if (type == 'message' && !_notificationTapStream.hasListener) {
      _pendingMessageTapData = payload;
      debugPrint(
        '[FCM_TAP] Stored pending message tap senderId=${payload['senderId']} senderName=${payload['senderName']}',
      );
      return;
    }

    if (type == 'call' && !_notificationTapStream.hasListener) {
      _pendingCallTapData = Map<String, String?>.from(payload);
      debugPrint(
        '[FCM_TAP] Stored pending call tap callId=${payload['callId']} callerId=${payload['callerId']}',
      );
      return;
    }

    _notificationTapStream.add(payload);
  }

  void dispose() {
    _notificationTapStream.close();
  }
}
