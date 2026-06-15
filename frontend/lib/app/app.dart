import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/user_provider.dart';
import '../providers/notification_provider.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/call_service.dart';
import '../services/push_service.dart';
import '../services/app_permissions_service.dart';
import '../screens/call_screen.dart';
import '../screens/login_screen.dart';
import '../screens/admin_screen.dart';
import '../screens/user_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/chat_screen.dart';
import '../widgets/active_call_overlay.dart';
import '../widgets/incoming_call_dialog.dart';

/// Глобальный ключ навигатора для доступа из CallService
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Открывает CallScreen из mini-call overlay при тапе.
///
/// Вынесена в глобальную область, чтобы быть доступной из MaterialApp.builder
/// (который находится в NApp, а не в _AppShellState).
void openCallScreenFromOverlay() {
  final callService = CallService();

  // Guard от дублирования: если CallScreen уже открыт — не открываем второй
  if (callService.isCallScreenOpen) {
    debugPrint('[APP] ⚠️ openCallScreenFromOverlay — call screen already open — ignoring');
    return;
  }

  final remoteUserId = callService.remoteUserId;
  final remoteUserName = callService.remoteUserName;

  if (remoteUserId == null) {
    debugPrint('[APP] ⚠️ openCallScreenFromOverlay — remoteUserId is null, cannot open CallScreen');
    return;
  }

  debugPrint('[APP] ✅ openCallScreenFromOverlay — opening CallScreen from overlay');
  callService.markCallScreenOpen();
  debugPrint('[APP] ✅ openCallScreenFromOverlay — opening CallScreen (userId=$remoteUserId, from=overlay)');
  Navigator.push(
    navigatorKey.currentContext!,
    MaterialPageRoute(
      settings: const RouteSettings(name: 'call_screen'),
      builder: (context) => CallScreen(
        userId: remoteUserId,
        userName: remoteUserName ?? 'Пользователь',
        isIncoming: false,
        from: 'overlay',
      ),
    ),
  );
}

class NApp extends StatelessWidget {
  const NApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(
          create: (_) => NotificationProvider(ApiService(), SocketService()),
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Natalie-Eng',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const _AppShell(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/admin': (context) => const AdminScreen(),
          '/user': (context) => const UserScreen(),
          '/notifications': (context) => const NotificationsScreen(),
        },
        builder: (context, child) {
          return Stack(
            children: [
              if (child != null) child,
              ActiveCallOverlay(
                onTap: openCallScreenFromOverlay,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Корневая обёртка: immersive mode + мониторинг сети + push-навигация.
///
/// ВАЖНО: _AppShell НЕ делает pushReplacementNamed после логина.
/// Вместо этого он рендерит нужный экран прямо в build().
/// Это гарантирует, что _AppShell всегда остаётся корневым контейнером
/// для ActiveCallOverlay, _listenIncomingCalls() и _listenPushNotificationTaps().
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> with WidgetsBindingObserver {
  bool _isChecking = true;
  bool _isOffline = false;

  // Храним, какой экран показывать (рендерится в build, а не через pushReplacement)
  Widget? _currentScreen;

  @override
  void initState() {
    super.initState();
    debugPrint('[APP_SHELL] ===== _AppShell.initState() BEGIN ====');
    WidgetsBinding.instance.addObserver(this);
    _enableStandardSystemUi();
    debugPrint('[APP_SHELL] Calling _checkAuth()');
    // Сначала проверяем авторизацию (и подключаем socket), потом инициализируем сервисы
    _checkAuth().then((_) => _initServices()).catchError((e) {
      debugPrint('[APP_SHELL] ❌ _checkAuth failed: $e');
      // Даже если _checkAuth упал, всё равно инициализируем сервисы
      _initServices();
    });
    _monitorConnectivity();
    debugPrint('[APP_SHELL] Calling _listenIncomingCalls()');
    _listenIncomingCalls();
    debugPrint('[APP_SHELL] Calling _listenPushNotificationTaps()');
    _listenPushNotificationTaps();
    debugPrint('[APP_SHELL] Calling _requestInitialPermissions() (unawaited)');
    _requestInitialPermissions(); // ТЗ 2: запрос разрешений при старте
    debugPrint('[APP_SHELL] Calling _listenCallState()');
    _listenCallState();
    debugPrint('[APP_SHELL] ===== _AppShell.initState() END ====');
  }

  /// Инициализирует глобальные сервисы (CallService).
  Future<void> _initServices() async {
    debugPrint('[APP_SHELL] _initServices() — BEGIN');
    try {
      await CallService().init();
      debugPrint('[APP_SHELL] _initServices() — CallService.init() OK');
    } catch (e, stack) {
      debugPrint('[APP_SHELL] 🔴 CRASH in _initServices (CallService.init): $e');
      debugPrint('[APP_SHELL] 🔴 StackTrace: $stack');
    }
    debugPrint('[APP_SHELL] _initServices() — END');
  }

  /// ТЗ 2: Запрос разрешений при старте приложения.
  void _requestInitialPermissions() {
    unawaited(AppPermissionsService().requestInitialPermissions());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingCallSubscription?.cancel();
    _pushTapSubscription?.cancel();
    _callStateSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enableStandardSystemUi();
    }

    // ТЗ 1: Завершать звонок, если приложение убито/выгружено из памяти
    if (state == AppLifecycleState.detached) {
      _handleAppKilled();
    }
  }

  /// ТЗ 1: Обрабатывает принудительное завершение приложения (swipe to kill / выгрузка из памяти).
  /// Завершает активный звонок, если он есть.
  void _handleAppKilled() {
    final callService = CallService();
    if (callService.currentCallId != null) {
      final callState = callService.state;
      if (callState == CallState.CALLING ||
          callState == CallState.RINGING ||
          callState == CallState.IN_CALL) {
        // Используем hardReset() вместо endCall(), т.к. при detached socket
        // socket может быть уже закрыт, и endCall() попытается отправить событие
        callService.hardReset();
      }
    }
  }

  /// Скрывает системные кнопки навигации (Immersive Mode)
  void _enableStandardSystemUi() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.white,
      systemNavigationBarDividerColor: Colors.black12,
      statusBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ));
  }

  StreamSubscription<Map<String, dynamic>>? _incomingCallSubscription;
  StreamSubscription<CallState>? _callStateSubscription;

  /// Слушает состояние звонка для автозакрытия IncomingCallDialog при завершении.
  void _listenCallState() {
    final callService = CallService();
    _callStateSubscription = callService.stateStream.listen((state) {
      if (!mounted) return;
      if (state == CallState.ENDED || state == CallState.IDLE) {
        // Guard: если диалог уже закрыт — не делаем pop()
        if (!callService.isIncomingDialogOpen) {
          debugPrint('[APP] 📞 _listenCallState — state=$state, dialog already closed — skipping pop');
          return;
        }
        debugPrint('[APP] 📞 _listenCallState — state=$state, dialog open — closing via pop');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (navigatorKey.currentContext == null) return;
          if (!navigatorKey.currentContext!.mounted) return;

          // Проверяем, что верхний route — это IncomingCallDialog
          final route = ModalRoute.of(navigatorKey.currentContext!);
          if (route?.settings.name != 'incoming_call_dialog') {
            debugPrint('[APP] ⚠️ _listenCallState — top route is "${route?.settings.name}", not incoming_call_dialog — skipping pop');
            return;
          }

          // Пробуем закрыть диалог, если он всё ещё открыт
          Navigator.of(navigatorKey.currentContext!).pop();
        });
      }
    });
  }

  /// Слушает входящие звонки и показывает IncomingCallDialog через fullscreen route.
  void _listenIncomingCalls() {
    _incomingCallSubscription = CallService().incomingCallStream.listen((data) {
      if (!mounted) return;

      final callerId = data['callerId'] as int;
      final callerName = data['callerName'] as String;
      final callId = data['callId'] as int? ?? 0;

      debugPrint('[APP] 📞 _listenIncomingCalls — data=$data');

      // Единая точка показа входящего диалога.
      // Все guard'ы (уже на звонке, уже открыт диалог и т.д.)
      // проверяются внутри _showIncomingCallDialog.
      _showIncomingCallDialog(
        callerId: callerId,
        callerName: callerName,
        callId: callId,
        source: 'socket',
      );
    });
  }

  StreamSubscription<Map<String, String?>>? _pushTapSubscription;

  /// Слушает нажатия на push-уведомления и выполняет навигацию.
  void _listenPushNotificationTaps() {
    _pushTapSubscription = PushService().onNotificationTap.listen((data) {
      if (!mounted) return;

      final type = data['type'];

      if (type == 'message') {
        // Открываем чат с отправителем
        final senderId = data['senderId'];
        if (senderId != null) {
          final userId = int.tryParse(senderId);
          if (userId != null) {
            final userName = data['senderName'] ?? 'Пользователь';
            Navigator.push(
              navigatorKey.currentContext!,
              MaterialPageRoute(
                builder: (context) => ChatScreen(
                  userId: userId,
                  userName: userName,
                ),
              ),
            );
          }
        }
      } else if (type == 'call') {
        // Для звонков — та же логика, что и для socket incoming:
        // показать IncomingCallDialog, а не сразу CallScreen
        _handleCallPushTap(data);
      }
    });

    // Проверяем, не было ли уже восстановлено состояние входящего звонка
    // из push-уведомления (getInitialMessage в PushService.init()).
    //
    // Сценарий: приложение было убито -> пришёл push -> пользователь тапнул ->
    // PushService.init() -> getInitialMessage() -> _emitTapFromData() ->
    // hydrateIncomingCallFromPush() -> state=RINGING.
    // НО: _emitTapFromData() эмитит в _notificationTapStream ДО того, как
    // _listenPushNotificationTaps() подписался на стрим (т.к. PushService.init()
    // вызывается в main() до runApp()). В результате событие теряется.
    //
    // Здесь мы проверяем: если CallService уже в RINGING, но диалог ещё не
    // показан — показываем диалог из данных CallService.
    _checkPendingIncomingCallFromPush();
  }

  /// Проверяет, не было ли восстановлено состояние входящего звонка из push
  /// до того, как подписка на стрим была установлена.
  ///
  /// Если CallService в RINGING — извлекает данные звонка из CallService
  /// и вызывает _showIncomingCallDialog(). Все guard'ы внутри _showIncomingCallDialog().
  void _checkPendingIncomingCallFromPush() {
    final callService = CallService();
    if (callService.state != CallState.RINGING) {
      debugPrint('[APP_PUSH_TAP] _checkPendingIncomingCallFromPush — state=${callService.state}, not RINGING — nothing to do');
      return;
    }

    final remoteUserId = callService.remoteUserId;
    final remoteUserName = callService.remoteUserName;
    final currentCallId = callService.currentCallId;

    if (remoteUserId == null) {
      debugPrint('[APP_PUSH_TAP] _checkPendingIncomingCallFromPush — remoteUserId is null, cannot show dialog');
      return;
    }

    debugPrint('[APP_PUSH_TAP] _checkPendingIncomingCallFromPush — state=RINGING — showing IncomingCallDialog (callerId=$remoteUserId, callerName=$remoteUserName)');

    _showIncomingCallDialog(
      callerId: remoteUserId,
      callerName: remoteUserName ?? 'Входящий звонок',
      callId: currentCallId ?? 0,
      source: 'push',
    );
  }

  /// Обрабатывает тап по call push-уведомлению.
  ///
  /// Пытается восстановить состояние входящего звонка из payload,
  /// затем вызывает единый метод _showIncomingCallDialog().
  /// Все guard'ы (уже открыт диалог / CallScreen) проверяются внутри
  /// _showIncomingCallDialog().
  void _handleCallPushTap(Map<String, String?> data) {
    final callerIdStr = data['callerId'];
    final callerName = data['callerName'] ?? 'Входящий звонок';
    final callIdStr = data['callId'];

    debugPrint('[APP_PUSH_TAP] _handleCallPushTap — callerId=$callerIdStr, callerName=$callerName');

    if (callerIdStr == null) {
      debugPrint('[APP_PUSH_TAP] ⚠️ callerId is null, cannot process');
      return;
    }

    final callerId = int.tryParse(callerIdStr);
    if (callerId == null) {
      debugPrint('[APP_PUSH_TAP] ⚠️ invalid callerId: $callerIdStr');
      return;
    }

    final callId = callIdStr != null ? int.tryParse(callIdStr) ?? 0 : 0;

    final callService = CallService();

    // Если state уже RINGING — socket уже установил состояние,
    // hydrate не нужен. Просто показываем диалог.
    if (callService.state == CallState.RINGING) {
      debugPrint('[APP_PUSH_TAP] state=RINGING — showing dialog without hydrate');
      _showIncomingCallDialog(
        callerId: callerId,
        callerName: callerName,
        callId: callId,
        source: 'push',
      );
      return;
    }

    // Если уже на звонке (CALLING / IN_CALL) — игнорируем push
    if (callService.state == CallState.CALLING ||
        callService.state == CallState.IN_CALL) {
      debugPrint('[APP_PUSH_TAP] ⚠️ already in call (state=${callService.state}) — ignoring push tap');
      return;
    }

    // Восстанавливаем состояние из push
    debugPrint('[APP_PUSH_TAP] Hydrating incoming call from push (state=${callService.state})');
    callService.hydrateIncomingCallFromPush(
      callId: callIdStr ?? '',
      callerId: callerIdStr,
      callerName: callerName,
    );

    _showIncomingCallDialog(
      callerId: callerId,
      callerName: callerName,
      callId: callId,
      source: 'push',
    );
  }

  /// Единый метод показа IncomingCallDialog.
  ///
  /// Используется как из socket-flow (_listenIncomingCalls), так и из
  /// push-flow (_handleCallPushTap / _checkPendingIncomingCallFromPush).
  ///
  /// Guard'ы (проверки):
  /// 1. Если уже открыт incoming_call_dialog → return
  /// 2. Если уже открыт CallScreen активного звонка → return
  void _showIncomingCallDialog({
    required int callerId,
    required String callerName,
    required int callId,
    required String source, // 'socket' или 'push'
  }) {
    final callService = CallService();

    final currentRoute = (navigatorKey.currentContext != null)
        ? ModalRoute.of(navigatorKey.currentContext!)?.settings.name
        : 'null';

    debugPrint('[APP] 📞 _showIncomingCallDialog — callerId=$callerId, callerName=$callerName, callId=$callId, source=$source');
    debugPrint('[APP] 📞 _showIncomingCallDialog — state=${callService.state}, isCallScreenOpen=${callService.isCallScreenOpen}, isIncomingDialogOpen=${callService.isIncomingDialogOpen}, isMinimized=${callService.isMinimized}, currentCallId=${callService.currentCallId}, route=$currentRoute');

    // Guard 1: уже открыт incoming_call_dialog
    if (callService.isIncomingDialogOpen) {
      // Stale-проверка: если текущий route не incoming_call_dialog — сбросить флаг
      if (currentRoute != 'incoming_call_dialog') {
        callService.markIncomingDialogClosed();
      } else {
        debugPrint('[APP] ⚠️ _showIncomingCallDialog — incoming dialog already open — ignoring');
        return;
      }
    }

    // Guard 2: уже открыт CallScreen активного звонка
    if (callService.isCallScreenOpen) {
      // Stale-проверка: если state IDLE или ENDED — сбросить флаг
      if (callService.state == CallState.IDLE || callService.state == CallState.ENDED) {
        callService.markCallScreenClosed();
      } else {
        debugPrint('[APP] ⚠️ _showIncomingCallDialog — call screen already open — ignoring');
        return;
      }
    }

    debugPrint('[APP] ✅ _showIncomingCallDialog — showing IncomingCallDialog (source=$source)');

    // Проверка mounted перед Navigator.push
    if (navigatorKey.currentContext == null) {
      debugPrint('[APP] ⚠️ _showIncomingCallDialog — navigatorKey.currentContext is null, cannot push');
      return;
    }
    if (!navigatorKey.currentContext!.mounted) {
      debugPrint('[APP] ⚠️ _showIncomingCallDialog — navigatorKey.currentContext is not mounted, cannot push');
      return;
    }

    // Отмечаем, что диалог открыт только перед реальным Navigator.push,
    // чтобы флаг не залипал, если до этого был ранний return.
    callService.markIncomingDialogOpen();

    // Показываем IncomingCallDialog как fullscreen route
    Navigator.push<bool>(
      navigatorKey.currentContext!,
      MaterialPageRoute(
        fullscreenDialog: true,
        settings: const RouteSettings(name: 'incoming_call_dialog'),
        builder: (context) => IncomingCallDialog(
          callerId: callerId,
          callerName: callerName,
          callId: callId,
        ),
      ),
    ).then((result) {
      // Диалог закрыт — сбрасываем флаг
      callService.markIncomingDialogClosed();

      if (result == true) {
        // Принято — вызываем acceptCall (fire-and-forget)
        debugPrint('[APP] ✅ _showIncomingCallDialog accepted — calling acceptCall()');
        unawaited(callService.acceptCall().catchError((e) {
          debugPrint('[APP] 🔴 acceptCall() threw: $e');
        }));

        // Открываем CallScreen в addPostFrameCallback, чтобы дать Flutter
        // завершить текущий фрейм (закрытие диалога) перед открытием нового экрана.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _openCallScreen(
            userId: callerId,
            userName: callerName,
            isIncoming: true,
            from: source,
          );
        });
      } else {
        // Отклонено или закрыто — вызываем rejectCall
        // Защита от двойного reject: если звонок уже завершён (state != RINGING),
        // не вызываем rejectCall повторно
        if (callService.state == CallState.RINGING) {
          debugPrint('[APP] ❌ _showIncomingCallDialog rejected/dismissed — calling rejectCall() (state=RINGING)');
          callService.rejectCall();
        } else {
          debugPrint('[APP] ⏭️ _showIncomingCallDialog dismissed — state=${callService.state}, skipping rejectCall (already ended)');
        }
      }
    });
  }

  /// Мониторинг подключения к интернету
  void _monitorConnectivity() {
    Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      final hasConnection = results.any((r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet);

      setState(() {
        _isOffline = !hasConnection;
      });

      if (!hasConnection) {
        CallService().handleConnectionLost();
      }
    });
  }

  Future<void> _checkAuth() async {
    debugPrint('[APP_SHELL] _checkAuth() — BEGIN');
    try {
      final auth = context.read<AuthProvider>();
      debugPrint('[APP_SHELL] _checkAuth() — AuthProvider obtained');
      final hasToken = await auth.checkAuth();
      debugPrint('[APP_SHELL] _checkAuth() — checkAuth() returned: hasToken=$hasToken');

      if (!mounted) {
        debugPrint('[APP_SHELL] _checkAuth() — not mounted after checkAuth, returning');
        return;
      }

      if (hasToken) {
        if (auth.currentUser == null) {
          debugPrint('[APP_SHELL] _checkAuth() — hasToken but currentUser is null, showing LoginScreen');
          _currentScreen = const LoginScreen();
        } else {
          debugPrint('[APP_SHELL] _checkAuth() — authenticated as user: ${auth.currentUser?.id}, isAdmin=${auth.isAdmin}');
          // После успешной аутентификации отправляем FCM token на backend
          unawaited(PushService().sendTokenToBackend());

          // Рендерим нужный экран прямо здесь, без pushReplacement
          _currentScreen = auth.isAdmin
              ? const AdminScreen()
              : const UserScreen();
        }
      } else {
        debugPrint('[APP_SHELL] _checkAuth() — no token, showing LoginScreen');
        _currentScreen = const LoginScreen();
      }

      debugPrint('[APP_SHELL] _checkAuth() — setting _isChecking=false, _currentScreen=$_currentScreen');
      setState(() {
        _isChecking = false;
      });
      debugPrint('[APP_SHELL] _checkAuth() — END');
    } catch (e, stack) {
      debugPrint('[APP_SHELL] 🔴 CRASH in _checkAuth: $e');
      debugPrint('[APP_SHELL] 🔴 StackTrace: $stack');
      // Fallback — показываем LoginScreen при ошибке
      if (mounted) {
        _currentScreen = const LoginScreen();
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Основной контент приложения
        if (_isChecking)
          const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          )
        else if (_currentScreen != null)
          _currentScreen!
        else
          const Scaffold(
            body: Center(
              child: Text('Ошибка загрузки приложения'),
            ),
          ),
        // Плашка "Нет соединения"
        if (_isOffline)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 4,
                  bottom: 8,
                  left: 16,
                  right: 16,
                ),
                color: Colors.red.shade700,
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Нет соединения с сетью. Ожидание восстановления...',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Единый метод открытия CallScreen.
  /// Вызывает markCallScreenOpen() и делает Navigator.push.
  void _openCallScreen({
    required int userId,
    required String userName,
    required bool isIncoming,
    required String from,
  }) {
    final callService = CallService();
    callService.markCallScreenOpen();
    debugPrint('[APP] ✅ _openCallScreen — opening CallScreen (userId=$userId, from=$from)');
    Navigator.push(
      navigatorKey.currentContext!,
      MaterialPageRoute(
        settings: const RouteSettings(name: 'call_screen'),
        builder: (context) => CallScreen(
          userId: userId,
          userName: userName,
          isIncoming: isIncoming,
          from: from,
        ),
      ),
    );
  }

}
