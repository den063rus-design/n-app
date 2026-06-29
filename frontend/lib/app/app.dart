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
import '../services/chat_navigation_service.dart';
import '../services/app_permissions_service.dart';
import '../config/api_config.dart';
import '../screens/call_screen.dart';
import '../screens/login_screen.dart';
import '../screens/admin_screen.dart';
import '../screens/user_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/chat_screen.dart';
import '../widgets/active_call_overlay.dart';
import '../widgets/incoming_call_dialog.dart';
import '../call_v2/call_v2_service.dart';
import '../call_v2/call_v2_debug.dart';
import '../call_v2/call_ui_intent.dart';
import '../call_v2/call_state.dart';

/// Глобальный ключ навигатора для доступа из CallService
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final CallRouteObserver callRouteObserver = CallRouteObserver();

class CallRouteObserver extends NavigatorObserver {
  String? currentRouteName;

  void _sync(Route<dynamic>? route) {
    currentRouteName = route?.settings.name;
    debugPrint('[APP_ROUTE] currentRoute=$currentRouteName');
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _sync(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _sync(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _sync(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _sync(previousRoute);
  }
}

/// Открывает CallScreen из mini-call overlay при тапе.
///
/// V2 primary: если V2 session активна — V2 сам управляет UI,
/// V1 fallback не нужен.
/// V1 fallback: если V2 не активна — используем старый путь.
///
/// Вынесена в глобальную область, чтобы быть доступной из MaterialApp.builder
/// (который находится в NApp, а не в _AppShellState).
void openCallScreenFromOverlay() {
  final v2Session = CallV2Service.instance.session;
  final callService = CallService();
  final currentRoute = callRouteObserver.currentRouteName;

  if (currentRoute == 'call_screen') {
    debugPrint('[APP] ?? openCallScreenFromOverlay � top route already call_screen');
    return;
  }

  if (callService.isCallScreenOpen &&
      callService.state != CallState.IDLE &&
      callService.state != CallState.ENDED) {
    debugPrint('[APP] ⚠️ openCallScreenFromOverlay — call screen already open — ignoring');
    return;
  }

  if (v2Session == null || !v2Session.isActive) {
    callV2Log('APP', 'overlay tap ignored — no active V2 session');
    return;
  }

  final remoteUserId = callService.remoteUserId;
  final remoteUserName = callService.remoteUserName;

  if (remoteUserId == null) {
    debugPrint('[APP] ⚠️ openCallScreenFromOverlay — remoteUserId is null, cannot open CallScreen');
    return;
  }

  callV2Log('APP', 'overlay tap opening call screen for userId=$remoteUserId');
  callService.markCallScreenOpen();
  debugPrint('[APP] ✅ openCallScreenFromOverlay — opening CallScreen (userId=$remoteUserId, from=overlay)');
  Navigator.push(
    navigatorKey.currentContext!,
    MaterialPageRoute(
      settings: const RouteSettings(name: 'call_screen'),
      builder: (context) => CallScreen(
        userId: remoteUserId,
        userName: remoteUserName ?? '������������',
        isIncoming: false,
        from: 'overlay',
      ),
    ),
  );
}

void _openCallScreenGlobal({
  required int userId,
  required String userName,
  required bool isIncoming,
  required String from,
}) {
  final context = navigatorKey.currentContext;
  if (context == null || !context.mounted) {
    debugPrint('[APP] ⚠️ _openCallScreenGlobal — navigator context unavailable');
    return;
  }

  final callService = CallService();
  if (callRouteObserver.currentRouteName == 'call_screen') {
    debugPrint('[APP] ?? _openCallScreenGlobal � top route already call_screen');
    return;
  }
  callService.markCallScreenOpen();
  debugPrint('[APP] ✅ _openCallScreenGlobal — opening CallScreen (userId=$userId, from=$from)');
  Navigator.push(
    context,
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

void showIncomingCallDialogFromService({
  required int callerId,
  required String callerName,
  required int callId,
  required String source,
}) {
  final callService = CallService();
  final context = navigatorKey.currentContext;
  final currentRoute = callRouteObserver.currentRouteName ?? 'null';

  debugPrint('[APP] GLOBAL showIncomingCallDialog begin — callerId=$callerId, callerName=$callerName, callId=$callId, source=$source');
  debugPrint('[APP] GLOBAL showIncomingCallDialog — state=${callService.state}, isCallScreenOpen=${callService.isCallScreenOpen}, isIncomingDialogOpen=${callService.isIncomingDialogOpen}, isMinimized=${callService.isMinimized}, currentCallId=${callService.currentCallId}, route=$currentRoute');

  if (callService.isIncomingDialogOpen) {
    if (currentRoute != 'incoming_call_dialog') {
      callService.markIncomingDialogClosed();
    } else {
      debugPrint('[APP] GLOBAL showIncomingCallDialog blocked because incoming dialog already open');
      return;
    }
  }

  if (callService.isCallScreenOpen) {
    if (callService.state == CallState.IDLE || callService.state == CallState.ENDED) {
      callService.markCallScreenClosed();
    } else if (currentRoute == 'call_screen') {
      debugPrint('[APP] GLOBAL showIncomingCallDialog blocked because top route is call_screen');
      return;
    } else {
      debugPrint('[APP] GLOBAL showIncomingCallDialog blocked because call screen already open');
      return;
    }
  }

  if (context == null) {
    debugPrint('[APP] ⚠️ GLOBAL showIncomingCallDialog — navigator context is null');
    if (source == 'pending_service' || source == 'state_fallback' || source == 'service' || source == 'v2_ui') {
      callService.restorePendingIncomingCall({
        'callerId': callerId,
        'callerName': callerName,
        'callId': callId,
      });
    }
    return;
  }
  if (!context.mounted) {
    debugPrint('[APP] ⚠️ GLOBAL showIncomingCallDialog — navigator context is not mounted');
    if (source == 'pending_service' || source == 'state_fallback' || source == 'service' || source == 'v2_ui') {
      callService.restorePendingIncomingCall({
        'callerId': callerId,
        'callerName': callerName,
        'callId': callId,
      });
    }
    return;
  }

  callService.markIncomingDialogOpen();
  debugPrint('[APP] GLOBAL showIncomingCallDialog scheduled route push');

  WidgetsBinding.instance.addPostFrameCallback((_) {
    final pushContext = navigatorKey.currentContext;
    final pushRoute = callRouteObserver.currentRouteName ?? 'null';

    if (pushContext == null || !pushContext.mounted) {
      debugPrint('[APP] ?? GLOBAL showIncomingCallDialog aborted � navigator context unavailable in post-frame');
      callService.markIncomingDialogClosed();
      return;
    }

    if (pushRoute == 'incoming_call_dialog') {
      debugPrint('[APP] GLOBAL showIncomingCallDialog skipped in post-frame � dialog already on top');
      callService.markIncomingDialogOpen();
      return;
    }

    debugPrint('[APP] GLOBAL showIncomingCallDialog pushed route');

    Navigator.push<bool>(
      pushContext,
      MaterialPageRoute(
        fullscreenDialog: true,
        settings: const RouteSettings(name: 'incoming_call_dialog'),
        builder: (context) => IncomingCallDialog(
          callerId: callerId,
          callerName: callerName,
          callId: callId,
        ),
      ),
    ).then((result) async {
      callService.markIncomingDialogClosed();

      if (result == true) {
        debugPrint('[APP] ✅ GLOBAL incoming dialog accepted — calling acceptCall()');
        try {
          await callService.acceptCall();

          if (callService.state != CallState.ACCEPTING &&
              callService.state != CallState.IN_CALL) {
            debugPrint('[APP] ⚠️ GLOBAL acceptCall completed but state=${callService.state} — NOT opening CallScreen');
            return;
          }

          _openCallScreenGlobal(
            userId: callerId,
            userName: callerName,
            isIncoming: true,
            from: source,
          );
        } catch (e) {
          debugPrint('[APP] 🔴 GLOBAL acceptCall failed: $e — NOT opening CallScreen');
        }
        return;
      }

      if (result == false && callService.state == CallState.RINGING) {
        debugPrint('[APP] ❌ GLOBAL incoming dialog rejected — calling rejectCall()');
        await callService.rejectCall();
      } else {
        debugPrint('[APP] ⏭️ GLOBAL incoming dialog dismissed/closed unexpectedly — result=$result state=${callService.state}, skipping rejectCall');
      }
    });
  });
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
        navigatorObservers: [callRouteObserver],
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
  static const bool v2Enabled = kUseCallV2;
  bool _isChecking = true;
  bool _isOffline = false;
  AppLifecycleState _lastLifecycleState = AppLifecycleState.resumed;
  AuthProvider? _authProvider;
  int? _pendingMessageChatUserId;
  String? _pendingMessageChatUserName;
  DateTime? _suppressMessageNavigationUntil;

  // Храним, какой экран показывать (рендерится в build, а не через pushReplacement)
  Widget? _currentScreen;

  // V2
  StreamSubscription<CallUiIntentV2>? _v2IntentSubscription;

  /// Latch: был ли уже показан V1 fallback incoming dialog для текущего звонка.
  /// Ставится ТОЛЬКО в authority path (_listenCallState при RINGING).
  /// Сбрасывается при ENDED/IDLE.
  bool _incomingFallbackConsumed = false;

  /// Единый helper: активна ли V2 session (не idle, не ended, не failed).
  bool _isV2SessionActive() {
    final session = CallV2Service.instance.session;
    if (session == null) return false;
    final state = session.state;
    return state != CallStateV2.idle &&
        state != CallStateV2.ended &&
        state != CallStateV2.failed;
  }

  /// Гарантированный path инициализации V2 после старта app shell.
  ///
  /// Вызывается после _checkAuth() в initState цепочке.
  /// Нужен для cold-start: _handleAuthStateChanged() может не сработать
  /// как listener, если пользователь уже авторизован и auth state не меняется.
  ///
  /// Безопасен для повторных вызовов — CallV2Service.init() имеет guard
  /// от повторной инициализации тем же userId.
  void _ensureCallV2InitializedFromCurrentAuthState() {
    if (!v2Enabled) {
      callV2Log('APP', 'ensure init skipped — v2 disabled');
      return;
    }
    try {
      final auth = context.read<AuthProvider>();
      if (!auth.isAuthenticated) {
        callV2Log('APP', 'ensure init skipped — not authenticated');
        return;
      }
      final userId = auth.currentUser?.id.toString();
      if (userId == null || userId.isEmpty) {
        callV2Log('APP', 'ensure init skipped — userId empty');
        return;
      }
      callV2Log('APP', 'ensure init localUserId=$userId');
      CallV2Service.instance.init(localUserId: userId);
      callV2Log('APP', 'ensure init done');
    } catch (e) {
      callV2Log('APP', 'ensure init error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[APP_SHELL] ===== _AppShell.initState() BEGIN ====');
    WidgetsBinding.instance.addObserver(this);
    _enableStandardSystemUi();
    debugPrint('[APP_SHELL] Calling _initServices()');
    _initServices().then((_) {
      debugPrint('[APP_SHELL] Calling _checkAuth()');
      return _checkAuth();
    }).then((_) {
      // Гарантированный path инициализации V2 после старта app shell.
      // Нужен для cold-start: _handleAuthStateChanged() может не сработать
      // как listener, если пользователь уже авторизован.
      _ensureCallV2InitializedFromCurrentAuthState();
    }).catchError((e) {
      debugPrint('[APP_SHELL] ❌ init/auth bootstrap failed: $e');
      if (mounted) {
        setState(() {
          _currentScreen = const LoginScreen();
          _isChecking = false;
        });
      }
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
    debugPrint('[APP_SHELL] Calling _setupV2CallListener()');
    _setupV2CallListener();
    debugPrint('[APP_SHELL] ===== _AppShell.initState() END ====');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final auth = context.read<AuthProvider>();
    if (identical(_authProvider, auth)) {
      return;
    }

    _authProvider?.removeListener(_handleAuthStateChanged);
    _authProvider = auth;
    _authProvider?.addListener(_handleAuthStateChanged);
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
    _authProvider?.removeListener(_handleAuthStateChanged);
    _incomingCallSubscription?.cancel();
    _pushTapSubscription?.cancel();
    _callStateSubscription?.cancel();
    _v2IntentSubscription?.cancel();
    super.dispose();
  }

  void _handleAuthStateChanged() {
    if (!mounted || _isChecking) {
      return;
    }

    final auth = _authProvider;
    if (auth == null) {
      return;
    }

    final Widget nextScreen = auth.isAuthenticated
        ? (auth.isAdmin ? const AdminScreen() : const UserScreen())
        : const LoginScreen();

    setState(() {
      _currentScreen = nextScreen;
    });

    _flushPendingMessageNavigation();

    // V2: инициализация после успешного auth (replay pending startup event)
    if (v2Enabled && auth.isAuthenticated) {
      final userId = auth.currentUser?.id.toString();
      if (userId != null && userId.isNotEmpty) {
        CallV2Service.instance.init(localUserId: userId);
        callV2Log('APP', '_handleAuthStateChanged init localUserId=$userId');
      }
    }

    debugPrint(
      '[APP_SHELL] auth state changed -> currentScreen=${nextScreen.runtimeType} '
      'authenticated=${auth.isAuthenticated} isAdmin=${auth.isAdmin}',
    );
  }

  void _storePendingMessageNavigation({
    required int userId,
    required String userName,
  }) {
    _pendingMessageChatUserId = userId;
    _pendingMessageChatUserName = userName;
    debugPrint(
      '[APP] stored pending message navigation userId=$userId userName=$userName',
    );
  }

  void _clearPendingMessageNavigation() {
    _pendingMessageChatUserId = null;
    _pendingMessageChatUserName = null;
  }

  void _armPostCallMessageNavigationSuppression(String source) {
    _suppressMessageNavigationUntil = DateTime.now().add(
      const Duration(seconds: 3),
    );
    debugPrint(
      '[APP] suppressing automatic message navigation after call end '
      '(source=$source, until=$_suppressMessageNavigationUntil)',
    );
  }

  bool _isPostCallMessageNavigationSuppressed() {
    final until = _suppressMessageNavigationUntil;
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _suppressMessageNavigationUntil = null;
      return false;
    }
    return true;
  }

  void _openChatFromNotification({
    required int userId,
    required String userName,
  }) {
    final auth = _authProvider;
    final context = navigatorKey.currentContext;

    if (_isChecking ||
        auth == null ||
        !auth.isAuthenticated ||
        context == null ||
        !context.mounted) {
      _storePendingMessageNavigation(userId: userId, userName: userName);
      return;
    }

    if (ChatNavigationService().isChatOpenWith(userId)) {
      _clearPendingMessageNavigation();
      return;
    }

    _clearPendingMessageNavigation();
    unawaited(
      PushService().cancelMessageNotificationForSender(
        senderId: userId.toString(),
        title: userName,
      ),
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          userId: userId,
          userName: userName,
          isAdmin: auth.isAdmin,
        ),
      ),
    );
  }

  void _flushPendingMessageNavigation() {
    final userId = _pendingMessageChatUserId;
    final userName = _pendingMessageChatUserName;
    final auth = _authProvider;

    if (userId == null ||
        userName == null ||
        _isChecking ||
        auth == null ||
        !auth.isAuthenticated) {
      return;
    }

    if (_isPostCallMessageNavigationSuppressed()) {
      debugPrint(
        '[APP] skipping _flushPendingMessageNavigation because call just ended '
        '(userId=$userId)',
      );
      _clearPendingMessageNavigation();
      PushService().clearPendingMessageTap();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isPostCallMessageNavigationSuppressed()) {
        debugPrint(
          '[APP] skipping deferred _flushPendingMessageNavigation because call just ended '
          '(userId=$userId)',
        );
        _clearPendingMessageNavigation();
        PushService().clearPendingMessageTap();
        return;
      }
      if (ChatNavigationService().isChatOpenWith(userId)) {
        _clearPendingMessageNavigation();
        return;
      }
      _openChatFromNotification(userId: userId, userName: userName);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lastLifecycleState = state;

    if (state == AppLifecycleState.resumed) {
      _enableStandardSystemUi();
      if (v2Enabled) {
        _checkPendingIncomingCallFromPush();
      }
    }

    // ?? 1: ????????? ??????, ???? ?????????? ?????/????????? ?? ??????
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

  /// AUTHORITY PATH для V1 fallback incoming dialog.
  ///
  /// Единственный метод, который открывает IncomingCallDialog.
  /// Все остальные entry points только:
  /// - проверяют latch
  /// - потребляют pending data
  /// - делегируют authority path
  ///
  /// Latch _incomingFallbackConsumed:
  /// - ставится ТОЛЬКО здесь (при RINGING, когда dialog показан)
  /// - сбрасывается при ENDED/IDLE
  void _listenCallState() {
    final callService = CallService();
    _callStateSubscription = callService.stateStream.listen((state) {
      if (!mounted) return;

      // ================================================================
      // Сброс latch при завершении звонка
      // ================================================================
      if (state == CallState.ENDED || state == CallState.IDLE) {
        _armPostCallMessageNavigationSuppression('call_state_$state');
        if (_incomingFallbackConsumed) {
          _incomingFallbackConsumed = false;
          debugPrint('[APP] _listenCallState — latch reset (state=$state)');
        }

        // Очищаем pending message navigation после завершения звонка,
        // чтобы не было самопроизвольного перехода в чат.
        if (_pendingMessageChatUserId != null || _pendingMessageChatUserName != null) {
          debugPrint('[APP] clearing pending message navigation after call end (userId=$_pendingMessageChatUserId)');
          _clearPendingMessageNavigation();
        }
        // Также чистим pending message tap в PushService.
        PushService().clearPendingMessageTap();
        debugPrint('[APP] clearing pending message tap after call end');

        // Guard: если диалог уже закрыт — не делаем pop()
        if (!callService.isIncomingDialogOpen) {
          debugPrint('[APP] _listenCallState — state=$state, dialog already closed — skipping pop');
          return;
        }
        debugPrint('[APP] _listenCallState — state=$state, dialog open — closing via pop');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (navigatorKey.currentContext == null) return;
          if (!navigatorKey.currentContext!.mounted) return;

          final routeName = callRouteObserver.currentRouteName;
          if (routeName != 'incoming_call_dialog') {
            debugPrint('[APP] _listenCallState — top route is "$routeName", not incoming_call_dialog — skipping pop');
            return;
          }

          Navigator.of(navigatorKey.currentContext!).pop();
        });
        return;
      }

      if (state == CallState.RINGING) {
        callV2Log(
          'APP',
          'stateStream RINGING callId=${callService.currentCallId} remoteUserId=${callService.remoteUserId}',
        );
        return;
      }
    });
  }

  /// V2: подписка на intentStream (вызывается в initState).
  /// Подписка происходит ДО init(), чтобы не пропустить replay.
  void _setupV2CallListener() {
    if (!v2Enabled) return;
    _v2IntentSubscription = CallV2Service.instance.intentStream.listen(_handleV2Intent);
    callV2Log('APP', 'intent listener subscribed');
  }

  /// V2: обработка UI intents.
  void _handleV2Intent(CallUiIntentV2 intent) {
    if (!mounted) return;
    callV2Log('APP', 'intent ${intent.runtimeType}');

    final isUiStartIntent = intent is ShowIncomingCallIntent ||
        intent is ShowOutgoingCallIntent ||
        intent is ShowActiveCallIntent;
    final isFinalIntent = intent is ShowCallEndedIntent ||
        intent is ShowCallFailedIntent ||
        intent is DismissCallScreenIntent;

    if (v2Enabled && isUiStartIntent) {
      if (intent is ShowIncomingCallIntent) {
        // Пробуем открыть dialog. Если context ещё не готов — сохраняем
        // pending incoming call для повторной попытки в _checkPendingIncomingCallFromPush().
        final context = navigatorKey.currentContext;
        if (context == null || !context.mounted) {
          callV2Log('APP', 'incoming intent arrived before navigator ready — saving pending');
          CallService().restorePendingIncomingCall({
            'callerId': intent.callerUserId,
            'callerName': intent.callerName ?? 'Incoming call',
            'callId': intent.callId,
          });
          return;
        }
        showIncomingCallDialogFromService(
          callerId: intent.callerUserId,
          callerName: intent.callerName ?? 'Incoming call',
          callId: intent.callId,
          source: 'v2_ui',
        );
        return;
      }

      if (intent is ShowOutgoingCallIntent) {
        if (callRouteObserver.currentRouteName != 'call_screen' &&
            !CallService().isCallScreenOpen) {
          _openCallScreenGlobal(
            userId: intent.calleeUserId,
            userName: intent.calleeName ?? 'User',
            isIncoming: false,
            from: 'v2_ui_outgoing',
          );
        }
        return;
      }

      if (intent is ShowActiveCallIntent) {
        final remoteUserId = intent.remoteUserId;
        if (remoteUserId != null &&
            remoteUserId != 0 &&
            callRouteObserver.currentRouteName != 'call_screen' &&
            !CallService().isCallScreenOpen) {
          _openCallScreenGlobal(
            userId: remoteUserId,
            userName: intent.remoteUserName ?? 'User',
            isIncoming: false,
            from: 'v2_ui_active',
          );
        }
        return;
      }
    }

    if (v2Enabled && isFinalIntent) {
      _armPostCallMessageNavigationSuppression('v2_final_intent_${intent.runtimeType}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final context = navigatorKey.currentContext;
        if (intent is ShowCallEndedIntent) {
          if (context != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(intent.endReason)),
            );
          }
          return;
        }
        if (intent is ShowCallFailedIntent) {
          if (context != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(intent.error)),
            );
          }
          return;
        }
        if (intent is DismissCallScreenIntent) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final dismissContext = navigatorKey.currentContext;
            final routeName = callRouteObserver.currentRouteName;
            if (dismissContext != null &&
                dismissContext.mounted &&
                (routeName == 'call_screen' || routeName == 'incoming_call_dialog')) {
              Navigator.of(dismissContext).pop();
            }
          });
        }
      });
    }
  }

  /// Слушает входящие звонки (socket path).
  ///
  /// НЕ открывает dialog напрямую — это делает ТОЛЬКО _listenCallState (authority path).
  /// Здесь только:
  /// - background: показать локальное уведомление
  /// - foreground: проверить latch, сохранить pending для authority path
  void _listenIncomingCalls() {
    debugPrint('[APP] _listenIncomingCalls — subscribing to incomingCallStream (backup path)');
    _incomingCallSubscription = CallService().incomingCallStream.listen(
      (data) {
        if (!mounted) return;

        final callerId = data['callerId'] as int;
        final callerName = data['callerName'] as String;
        final callId = data['callId'] as int? ?? 0;

        debugPrint('[APP] incoming socket event — callerId=$callerId, callerName=$callerName, callId=$callId');

        // Background check — ВСЕГДА первым, до любых V2/V1 проверок.
        // На Honor и других устройствах FCM не гарантирует heads-up уведомление,
        // поэтому показываем локальное уведомление при любом фоновом входящем звонке.
        final isForeground = _lastLifecycleState == AppLifecycleState.resumed ||
            _lastLifecycleState == AppLifecycleState.inactive;

        if (!isForeground) {
          debugPrint('[APP] incoming socket event while app is backgrounded — showing local call notification (regardless of FCM)');
          unawaited(PushService().showIncomingCallNotificationFromSocket(
            callId: callId.toString(),
            callerId: callerId.toString(),
            callerName: callerName,
          ));
          return;
        }

        if (v2Enabled) {
          callV2Log('APP', 'socket incoming observed in foreground callId=$callId callerId=$callerId');
        }
      },
      onError: (error, stackTrace) {
        debugPrint('[APP] _listenIncomingCalls — stream error: $error');
        debugPrint('[APP] _listenIncomingCalls — stackTrace: $stackTrace');
      },
    );

    if (v2Enabled) {
      _checkPendingIncomingCallFromPush();
    }
  }

  StreamSubscription<Map<String, String?>>? _pushTapSubscription;

  /// Слушает нажатия на push-уведомления и выполняет навигацию.
  void _listenPushNotificationTaps() {
    _pushTapSubscription = PushService().onNotificationTap.listen((data) {
      if (!mounted) return;

      final type = data['type'];

      if (type == 'message') {
        PushService().clearPendingMessageTap();
        final senderId = data['senderId'];
        if (senderId != null) {
          final userId = int.tryParse(senderId);
          if (userId != null) {
            final userName = data['senderName'] ?? '������������';
            _openChatFromNotification(
              userId: userId,
              userName: userName,
            );
          }
        }
      } else if (type == 'call') {
        PushService().clearPendingCallTap();
        callV2Log('APP', 'call notification tap observed by app shell');
      }
    });

    _checkPendingMessageTap();

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
    // показан — authority path получит stateStream и покажет dialog.
    _checkPendingIncomingCallFromPush();
  }

  void _checkPendingMessageTap() {
    if (_isPostCallMessageNavigationSuppressed()) {
      debugPrint('[APP] skipping _checkPendingMessageTap because call just ended');
      PushService().clearPendingMessageTap();
      _clearPendingMessageNavigation();
      return;
    }

    final pending = PushService().consumePendingMessageTap();
    if (pending == null || pending['type'] != 'message') {
      return;
    }

    final senderId = pending['senderId'];
    final userId = senderId != null ? int.tryParse(senderId) : null;
    if (userId == null) {
      return;
    }

    final userName = pending['senderName'] ?? '������������';
    debugPrint(
      '[APP] restoring pending message tap userId=$userId userName=$userName',
    );
    _openChatFromNotification(
      userId: userId,
      userName: userName,
    );
  }

  /// Cold-start rescue bridge для killed app + push tap.
  ///
  /// V2 primary: V2 сам поднимает incoming flow из push tap через
  /// handleIncomingFromPushTap() в push_service.dart.
  ///
  /// Здесь — повторная попытка открыть incoming dialog, если первый
  /// ShowIncomingCallIntent пришёл слишком рано (context был null).
  /// В этом случае _handleV2Intent сохранил pending incoming call через
  /// restorePendingIncomingCall(), и здесь мы его потребляем.
  ///
  /// Больше НЕ открывает dialog напрямую как V1 rescue.
  void _checkPendingIncomingCallFromPush() {
    final callService = CallService();

    // V2 replay path: если V2 session активна, но dialog ещё не открыт —
    // пробуем открыть через V2 (source='v2_ui').
    if (v2Enabled) {
      if (!_isV2SessionActive()) {
        callV2Log('APP', 'pending incoming replay skipped — no active V2 session');
        return;
      }

      // Guard: UI уже открыт
      if (callService.isIncomingDialogOpen || callService.isCallScreenOpen) {
        callV2Log('APP', 'pending incoming replay skipped — UI already open');
        return;
      }

      // Пробуем потребить pending incoming call (сохранённый _handleV2Intent)
      final pending = callService.consumePendingIncomingCall();
      if (pending != null) {
        final callerId = pending['callerId'] as int?;
        final callerName = pending['callerName'] as String?;
        final callId = pending['callId'] as int? ?? 0;
        if (callerId != null) {
          callV2Log('APP', 'pending incoming replay open dialog callerId=$callerId callId=$callId');
          showIncomingCallDialogFromService(
            callerId: callerId,
            callerName: callerName ?? 'Incoming call',
            callId: callId,
            source: 'v2_ui',
          );
        }
      }

      callV2Log('APP', 'pending incoming replay finished');
      return;
    }
    callV2Log('APP', 'pending incoming replay skipped — V2 disabled');
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
          debugPrint('[APP] token sync after auth begin');
          unawaited(PushService().syncTokenToBackend().then((_) {
            debugPrint('[APP] token sync after auth success');
          }).catchError((e) {
            debugPrint('[APP] token sync after auth fail: $e');
          }));

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
      _flushPendingMessageNavigation();
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
              child: Text('������ �������� ����������'),
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
                        '��� ���������� � �����. �������� ��������������...',
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

}

