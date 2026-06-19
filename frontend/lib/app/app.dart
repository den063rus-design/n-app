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

/// Р“Р»РѕР±Р°Р»СЊРЅС‹Р№ РєР»СЋС‡ РЅР°РІРёРіР°С‚РѕСЂР° РґР»СЏ РґРѕСЃС‚СѓРїР° РёР· CallService
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

/// РћС‚РєСЂС‹РІР°РµС‚ CallScreen РёР· mini-call overlay РїСЂРё С‚Р°РїРµ.
///
/// Р’С‹РЅРµСЃРµРЅР° РІ РіР»РѕР±Р°Р»СЊРЅСѓСЋ РѕР±Р»Р°СЃС‚СЊ, С‡С‚РѕР±С‹ Р±С‹С‚СЊ РґРѕСЃС‚СѓРїРЅРѕР№ РёР· MaterialApp.builder
/// (РєРѕС‚РѕСЂС‹Р№ РЅР°С…РѕРґРёС‚СЃСЏ РІ NApp, Р° РЅРµ РІ _AppShellState).
void openCallScreenFromOverlay() {
  final callService = CallService();
  final currentRoute = callRouteObserver.currentRouteName;

  if (currentRoute == 'call_screen') {
    debugPrint('[APP] ⚠️ openCallScreenFromOverlay — top route already call_screen');
    return;
  }

  if (callService.isCallScreenOpen &&
      callService.state != CallState.IDLE &&
      callService.state != CallState.ENDED) {
    debugPrint('[APP] вљ пёЏ openCallScreenFromOverlay вЂ” call screen already open вЂ” ignoring');
    return;
  }

  final remoteUserId = callService.remoteUserId;
  final remoteUserName = callService.remoteUserName;

  if (remoteUserId == null) {
    debugPrint('[APP] вљ пёЏ openCallScreenFromOverlay вЂ” remoteUserId is null, cannot open CallScreen');
    return;
  }

  debugPrint('[APP] вњ… openCallScreenFromOverlay вЂ” opening CallScreen from overlay');
  callService.markCallScreenOpen();
  debugPrint('[APP] вњ… openCallScreenFromOverlay вЂ” opening CallScreen (userId=$remoteUserId, from=overlay)');
  Navigator.push(
    navigatorKey.currentContext!,
    MaterialPageRoute(
      settings: const RouteSettings(name: 'call_screen'),
      builder: (context) => CallScreen(
        userId: remoteUserId,
        userName: remoteUserName ?? 'РџРѕР»СЊР·РѕРІР°С‚РµР»СЊ',
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
    debugPrint('[APP] вљ пёЏ _openCallScreenGlobal вЂ” navigator context unavailable');
    return;
  }

  final callService = CallService();
  if (callRouteObserver.currentRouteName == 'call_screen') {
    debugPrint('[APP] ⚠️ _openCallScreenGlobal — top route already call_screen');
    return;
  }
  callService.markCallScreenOpen();
  debugPrint('[APP] вњ… _openCallScreenGlobal вЂ” opening CallScreen (userId=$userId, from=$from)');
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

  debugPrint('[APP] GLOBAL showIncomingCallDialog begin вЂ” callerId=$callerId, callerName=$callerName, callId=$callId, source=$source');
  debugPrint('[APP] GLOBAL showIncomingCallDialog вЂ” state=${callService.state}, isCallScreenOpen=${callService.isCallScreenOpen}, isIncomingDialogOpen=${callService.isIncomingDialogOpen}, isMinimized=${callService.isMinimized}, currentCallId=${callService.currentCallId}, route=$currentRoute');

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
    debugPrint('[APP] вљ пёЏ GLOBAL showIncomingCallDialog вЂ” navigator context is null');
    if (source == 'pending_service' || source == 'state_fallback' || source == 'service') {
      callService.restorePendingIncomingCall({
        'callerId': callerId,
        'callerName': callerName,
        'callId': callId,
      });
    }
    return;
  }
  if (!context.mounted) {
    debugPrint('[APP] вљ пёЏ GLOBAL showIncomingCallDialog вЂ” navigator context is not mounted');
    if (source == 'pending_service' || source == 'state_fallback' || source == 'service') {
      callService.restorePendingIncomingCall({
        'callerId': callerId,
        'callerName': callerName,
        'callId': callId,
      });
    }
    return;
  }

  callService.markIncomingDialogOpen();
  debugPrint('[APP] GLOBAL showIncomingCallDialog pushed route');

  Navigator.push<bool>(
    context,
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
      debugPrint('[APP] вњ… GLOBAL incoming dialog accepted вЂ” calling acceptCall()');
      try {
        await callService.acceptCall();

        if (callService.state != CallState.ACCEPTING &&
            callService.state != CallState.IN_CALL) {
          debugPrint('[APP] вљ пёЏ GLOBAL acceptCall completed but state=${callService.state} вЂ” NOT opening CallScreen');
          return;
        }

        _openCallScreenGlobal(
          userId: callerId,
          userName: callerName,
          isIncoming: true,
          from: source,
        );
      } catch (e) {
        debugPrint('[APP] рџ”ґ GLOBAL acceptCall failed: $e вЂ” NOT opening CallScreen');
      }
      return;
    }

    if (result == false && callService.state == CallState.RINGING) {
      debugPrint('[APP] вќЊ GLOBAL incoming dialog rejected вЂ” calling rejectCall()');
      await callService.rejectCall();
    } else {
      debugPrint('[APP] вЏ­пёЏ GLOBAL incoming dialog dismissed/closed unexpectedly вЂ” result=$result state=${callService.state}, skipping rejectCall');
    }
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

/// РљРѕСЂРЅРµРІР°СЏ РѕР±С‘СЂС‚РєР°: immersive mode + РјРѕРЅРёС‚РѕСЂРёРЅРі СЃРµС‚Рё + push-РЅР°РІРёРіР°С†РёСЏ.
///
/// Р’РђР–РќРћ: _AppShell РќР• РґРµР»Р°РµС‚ pushReplacementNamed РїРѕСЃР»Рµ Р»РѕРіРёРЅР°.
/// Р’РјРµСЃС‚Рѕ СЌС‚РѕРіРѕ РѕРЅ СЂРµРЅРґРµСЂРёС‚ РЅСѓР¶РЅС‹Р№ СЌРєСЂР°РЅ РїСЂСЏРјРѕ РІ build().
/// Р­С‚Рѕ РіР°СЂР°РЅС‚РёСЂСѓРµС‚, С‡С‚Рѕ _AppShell РІСЃРµРіРґР° РѕСЃС‚Р°С‘С‚СЃСЏ РєРѕСЂРЅРµРІС‹Рј РєРѕРЅС‚РµР№РЅРµСЂРѕРј
/// РґР»СЏ ActiveCallOverlay, _listenIncomingCalls() Рё _listenPushNotificationTaps().
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> with WidgetsBindingObserver {
  bool _isChecking = true;
  bool _isOffline = false;
  AppLifecycleState _lastLifecycleState = AppLifecycleState.resumed;
  AuthProvider? _authProvider;

  // РҐСЂР°РЅРёРј, РєР°РєРѕР№ СЌРєСЂР°РЅ РїРѕРєР°Р·С‹РІР°С‚СЊ (СЂРµРЅРґРµСЂРёС‚СЃСЏ РІ build, Р° РЅРµ С‡РµСЂРµР· pushReplacement)
  Widget? _currentScreen;

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
    }).catchError((e) {
      debugPrint('[APP_SHELL] вќЊ init/auth bootstrap failed: $e');
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
    _requestInitialPermissions(); // РўР— 2: Р·Р°РїСЂРѕСЃ СЂР°Р·СЂРµС€РµРЅРёР№ РїСЂРё СЃС‚Р°СЂС‚Рµ
    debugPrint('[APP_SHELL] Calling _listenCallState()');
    _listenCallState();
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

  /// РРЅРёС†РёР°Р»РёР·РёСЂСѓРµС‚ РіР»РѕР±Р°Р»СЊРЅС‹Рµ СЃРµСЂРІРёСЃС‹ (CallService).
  Future<void> _initServices() async {
    debugPrint('[APP_SHELL] _initServices() вЂ” BEGIN');
    try {
      await CallService().init();
      debugPrint('[APP_SHELL] _initServices() вЂ” CallService.init() OK');
    } catch (e, stack) {
      debugPrint('[APP_SHELL] рџ”ґ CRASH in _initServices (CallService.init): $e');
      debugPrint('[APP_SHELL] рџ”ґ StackTrace: $stack');
    }
    debugPrint('[APP_SHELL] _initServices() вЂ” END');
  }

  /// РўР— 2: Р—Р°РїСЂРѕСЃ СЂР°Р·СЂРµС€РµРЅРёР№ РїСЂРё СЃС‚Р°СЂС‚Рµ РїСЂРёР»РѕР¶РµРЅРёСЏ.
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

    debugPrint(
      '[APP_SHELL] auth state changed -> currentScreen=${nextScreen.runtimeType} '
      'authenticated=${auth.isAuthenticated} isAdmin=${auth.isAdmin}',
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lastLifecycleState = state;

    if (state == AppLifecycleState.resumed) {
      _enableStandardSystemUi();
      _checkPendingIncomingCallFromService();
      _checkPendingIncomingCallFromPush();
    }

    // ?? 1: ????????? ??????, ???? ?????????? ?????/????????? ?? ??????
    if (state == AppLifecycleState.detached) {
      _handleAppKilled();
    }
  }

  /// РўР— 1: РћР±СЂР°Р±Р°С‚С‹РІР°РµС‚ РїСЂРёРЅСѓРґРёС‚РµР»СЊРЅРѕРµ Р·Р°РІРµСЂС€РµРЅРёРµ РїСЂРёР»РѕР¶РµРЅРёСЏ (swipe to kill / РІС‹РіСЂСѓР·РєР° РёР· РїР°РјСЏС‚Рё).
  /// Р—Р°РІРµСЂС€Р°РµС‚ Р°РєС‚РёРІРЅС‹Р№ Р·РІРѕРЅРѕРє, РµСЃР»Рё РѕРЅ РµСЃС‚СЊ.
  void _handleAppKilled() {
    final callService = CallService();
    if (callService.currentCallId != null) {
      final callState = callService.state;
      if (callState == CallState.CALLING ||
          callState == CallState.RINGING ||
          callState == CallState.IN_CALL) {
        // РСЃРїРѕР»СЊР·СѓРµРј hardReset() РІРјРµСЃС‚Рѕ endCall(), С‚.Рє. РїСЂРё detached socket
        // socket РјРѕР¶РµС‚ Р±С‹С‚СЊ СѓР¶Рµ Р·Р°РєСЂС‹С‚, Рё endCall() РїРѕРїС‹С‚Р°РµС‚СЃСЏ РѕС‚РїСЂР°РІРёС‚СЊ СЃРѕР±С‹С‚РёРµ
        callService.hardReset();
      }
    }
  }

  /// РЎРєСЂС‹РІР°РµС‚ СЃРёСЃС‚РµРјРЅС‹Рµ РєРЅРѕРїРєРё РЅР°РІРёРіР°С†РёРё (Immersive Mode)
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

  /// РЎР»СѓС€Р°РµС‚ СЃРѕСЃС‚РѕСЏРЅРёРµ Р·РІРѕРЅРєР° РґР»СЏ Р°РІС‚РѕР·Р°РєСЂС‹С‚РёСЏ IncomingCallDialog РїСЂРё Р·Р°РІРµСЂС€РµРЅРёРё.
  void _listenCallState() {
    final callService = CallService();
    _callStateSubscription = callService.stateStream.listen((state) {
      if (!mounted) return;
      if (state == CallState.RINGING) {
        if (callService.isIncomingDialogOpen || callService.isCallScreenOpen) {
          debugPrint('[APP] _listenCallState вЂ” state=RINGING, UI already open вЂ” skipping fallback');
          return;
        }

        final callerId = callService.remoteUserId;
        final callerName = callService.remoteUserName;
        final callId = callService.currentCallId ?? 0;

        if (callerId == null) {
          debugPrint('[APP] _listenCallState вЂ” state=RINGING but remoteUserId is null');
          return;
        }

        debugPrint(
          '[APP] _listenCallState вЂ” state=RINGING fallback -> show dialog '
          '(callerId=$callerId, callerName=$callerName, callId=$callId)',
        );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showIncomingCallDialogFromService(
            callerId: callerId,
            callerName: callerName ?? 'Р’С…РѕРґСЏС‰РёР№ Р·РІРѕРЅРѕРє',
            callId: callId,
            source: 'state_fallback',
          );
        });
        return;
      }

      if (state == CallState.ENDED || state == CallState.IDLE) {
        // Guard: РµСЃР»Рё РґРёР°Р»РѕРі СѓР¶Рµ Р·Р°РєСЂС‹С‚ вЂ” РЅРµ РґРµР»Р°РµРј pop()
        if (!callService.isIncomingDialogOpen) {
          debugPrint('[APP] рџ“ћ _listenCallState вЂ” state=$state, dialog already closed вЂ” skipping pop');
          return;
        }
        debugPrint('[APP] рџ“ћ _listenCallState вЂ” state=$state, dialog open вЂ” closing via pop');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (navigatorKey.currentContext == null) return;
          if (!navigatorKey.currentContext!.mounted) return;

          final routeName = callRouteObserver.currentRouteName;
          if (routeName != 'incoming_call_dialog') {
            debugPrint('[APP] вљ пёЏ _listenCallState вЂ” top route is "$routeName", not incoming_call_dialog вЂ” skipping pop');
            return;
          }

          Navigator.of(navigatorKey.currentContext!).pop();
        });
      }
    });
  }

  /// РЎР»СѓС€Р°РµС‚ РІС…РѕРґСЏС‰РёРµ Р·РІРѕРЅРєРё Рё РїРѕРєР°Р·С‹РІР°РµС‚ IncomingCallDialog С‡РµСЂРµР· fullscreen route.
  void _listenIncomingCalls() {
    debugPrint('[APP] _listenIncomingCalls вЂ” subscribing to incomingCallStream (backup path)');
    _incomingCallSubscription = CallService().incomingCallStream.listen(
      (data) {
        if (!mounted) return;

        final callerId = data['callerId'] as int;
        final callerName = data['callerName'] as String;
        final callId = data['callId'] as int? ?? 0;

        debugPrint('[APP] рџ“ћ APP incoming socket event (backup path) вЂ” callerId=$callerId, callerName=$callerName, callId=$callId');

        final isForeground = _lastLifecycleState == AppLifecycleState.resumed ||
            _lastLifecycleState == AppLifecycleState.inactive;

        if (!isForeground) {
          debugPrint('[APP] incoming socket event while app is backgrounded ? showing local call notification instead of dialog');
          unawaited(PushService().showIncomingCallNotificationFromSocket(
            callId: callId.toString(),
            callerId: callerId.toString(),
            callerName: callerName,
          ));
          return;
        }

        // ?????? ????? ?????? ????????? ???????.
        // ??? guard'? (??? ?? ??????, ??? ?????? ?????? ? ?.?.)
        // ??????????? ?????? _showIncomingCallDialog.
        showIncomingCallDialogFromService(
          callerId: callerId,
          callerName: callerName,
          callId: callId,
          source: 'socket',
        );
      },
      onError: (error, stackTrace) {
        debugPrint('[APP] _listenIncomingCalls вЂ” stream error: $error');
        debugPrint('[APP] _listenIncomingCalls вЂ” stackTrace: $stackTrace');
      },
    );

    _checkPendingIncomingCallFromService();
  }

  StreamSubscription<Map<String, String?>>? _pushTapSubscription;

  /// РЎР»СѓС€Р°РµС‚ РЅР°Р¶Р°С‚РёСЏ РЅР° push-СѓРІРµРґРѕРјР»РµРЅРёСЏ Рё РІС‹РїРѕР»РЅСЏРµС‚ РЅР°РІРёРіР°С†РёСЋ.
  void _listenPushNotificationTaps() {
    _pushTapSubscription = PushService().onNotificationTap.listen((data) {
      if (!mounted) return;

      final type = data['type'];

      if (type == 'message') {
        // РћС‚РєСЂС‹РІР°РµРј С‡Р°С‚ СЃ РѕС‚РїСЂР°РІРёС‚РµР»РµРј
        final senderId = data['senderId'];
        if (senderId != null) {
          final userId = int.tryParse(senderId);
          if (userId != null) {
            final userName = data['senderName'] ?? 'РџРѕР»СЊР·РѕРІР°С‚РµР»СЊ';
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
        // Р”Р»СЏ Р·РІРѕРЅРєРѕРІ вЂ” С‚Р° Р¶Рµ Р»РѕРіРёРєР°, С‡С‚Рѕ Рё РґР»СЏ socket incoming:
        // РїРѕРєР°Р·Р°С‚СЊ IncomingCallDialog, Р° РЅРµ СЃСЂР°Р·Сѓ CallScreen
        _handleCallPushTap(data);
      }
    });

    // РџСЂРѕРІРµСЂСЏРµРј, РЅРµ Р±С‹Р»Рѕ Р»Рё СѓР¶Рµ РІРѕСЃСЃС‚Р°РЅРѕРІР»РµРЅРѕ СЃРѕСЃС‚РѕСЏРЅРёРµ РІС…РѕРґСЏС‰РµРіРѕ Р·РІРѕРЅРєР°
    // РёР· push-СѓРІРµРґРѕРјР»РµРЅРёСЏ (getInitialMessage РІ PushService.init()).
    //
    // РЎС†РµРЅР°СЂРёР№: РїСЂРёР»РѕР¶РµРЅРёРµ Р±С‹Р»Рѕ СѓР±РёС‚Рѕ -> РїСЂРёС€С‘Р» push -> РїРѕР»СЊР·РѕРІР°С‚РµР»СЊ С‚Р°РїРЅСѓР» ->
    // PushService.init() -> getInitialMessage() -> _emitTapFromData() ->
    // hydrateIncomingCallFromPush() -> state=RINGING.
    // РќРћ: _emitTapFromData() СЌРјРёС‚РёС‚ РІ _notificationTapStream Р”Рћ С‚РѕРіРѕ, РєР°Рє
    // _listenPushNotificationTaps() РїРѕРґРїРёСЃР°Р»СЃСЏ РЅР° СЃС‚СЂРёРј (С‚.Рє. PushService.init()
    // РІС‹Р·С‹РІР°РµС‚СЃСЏ РІ main() РґРѕ runApp()). Р’ СЂРµР·СѓР»СЊС‚Р°С‚Рµ СЃРѕР±С‹С‚РёРµ С‚РµСЂСЏРµС‚СЃСЏ.
    //
    // Р—РґРµСЃСЊ РјС‹ РїСЂРѕРІРµСЂСЏРµРј: РµСЃР»Рё CallService СѓР¶Рµ РІ RINGING, РЅРѕ РґРёР°Р»РѕРі РµС‰С‘ РЅРµ
    // РїРѕРєР°Р·Р°РЅ вЂ” РїРѕРєР°Р·С‹РІР°РµРј РґРёР°Р»РѕРі РёР· РґР°РЅРЅС‹С… CallService.
    _checkPendingIncomingCallFromPush();
  }

  /// РџСЂРѕРІРµСЂСЏРµС‚, РЅРµ Р±С‹Р»Рѕ Р»Рё РІРѕСЃСЃС‚Р°РЅРѕРІР»РµРЅРѕ СЃРѕСЃС‚РѕСЏРЅРёРµ РІС…РѕРґСЏС‰РµРіРѕ Р·РІРѕРЅРєР° РёР· push
  /// РґРѕ С‚РѕРіРѕ, РєР°Рє РїРѕРґРїРёСЃРєР° РЅР° СЃС‚СЂРёРј Р±С‹Р»Р° СѓСЃС‚Р°РЅРѕРІР»РµРЅР°.
  ///
  /// Р•СЃР»Рё CallService РІ RINGING вЂ” РёР·РІР»РµРєР°РµС‚ РґР°РЅРЅС‹Рµ Р·РІРѕРЅРєР° РёР· CallService
  /// Рё РІС‹Р·С‹РІР°РµС‚ _showIncomingCallDialog(). Р’СЃРµ guard'С‹ РІРЅСѓС‚СЂРё _showIncomingCallDialog().
  void _checkPendingIncomingCallFromPush() {
    final callService = CallService();
    if (callService.state != CallState.RINGING) {
      debugPrint('[APP] _checkPendingIncomingCallFromPush вЂ” state=${callService.state}, not RINGING вЂ” nothing to do');
      return;
    }

    final remoteUserId = callService.remoteUserId;
    final remoteUserName = callService.remoteUserName;
    final currentCallId = callService.currentCallId;

    if (remoteUserId == null) {
      debugPrint('[APP] _checkPendingIncomingCallFromPush вЂ” remoteUserId is null, cannot show dialog');
      return;
    }

    debugPrint('[APP] _checkPendingIncomingCallFromPush вЂ” state=RINGING вЂ” showing IncomingCallDialog (callerId=$remoteUserId, callerName=$remoteUserName)');

    showIncomingCallDialogFromService(
      callerId: remoteUserId,
      callerName: remoteUserName ?? 'Р’С…РѕРґСЏС‰РёР№ Р·РІРѕРЅРѕРє',
      callId: currentCallId ?? 0,
      source: 'push',
    );
  }

  void _checkPendingIncomingCallFromService() {
    final callService = CallService();
    final pending = callService.consumePendingIncomingCall();

    if (pending == null) {
      debugPrint('[APP] _checkPendingIncomingCallFromService вЂ” no pending incoming call');
      return;
    }

    final callerId = pending['callerId'] as int?;
    final callerName = pending['callerName'] as String?;
    final callId = pending['callId'] as int? ?? 0;

    if (callerId == null) {
      debugPrint('[APP] _checkPendingIncomingCallFromService вЂ” pending callerId is null');
      return;
    }

    debugPrint(
      '[APP] _checkPendingIncomingCallFromService вЂ” showing pending incoming call '
      '(callerId=$callerId, callerName=$callerName, callId=$callId)',
    );

    showIncomingCallDialogFromService(
      callerId: callerId,
      callerName: callerName ?? 'Р’С…РѕРґСЏС‰РёР№ Р·РІРѕРЅРѕРє',
      callId: callId,
      source: 'pending_service',
    );
  }

  /// РћР±СЂР°Р±Р°С‚С‹РІР°РµС‚ С‚Р°Рї РїРѕ call push-СѓРІРµРґРѕРјР»РµРЅРёСЋ.
  ///
  /// РџС‹С‚Р°РµС‚СЃСЏ РІРѕСЃСЃС‚Р°РЅРѕРІРёС‚СЊ СЃРѕСЃС‚РѕСЏРЅРёРµ РІС…РѕРґСЏС‰РµРіРѕ Р·РІРѕРЅРєР° РёР· payload,
  /// Р·Р°С‚РµРј РІС‹Р·С‹РІР°РµС‚ РµРґРёРЅС‹Р№ РјРµС‚РѕРґ _showIncomingCallDialog().
  /// Р’СЃРµ guard'С‹ (СѓР¶Рµ РѕС‚РєСЂС‹С‚ РґРёР°Р»РѕРі / CallScreen) РїСЂРѕРІРµСЂСЏСЋС‚СЃСЏ РІРЅСѓС‚СЂРё
  /// _showIncomingCallDialog().
  void _handleCallPushTap(Map<String, String?> data) {
    final callerIdStr = data['callerId'];
    final callerName = data['callerName'] ?? 'Р’С…РѕРґСЏС‰РёР№ Р·РІРѕРЅРѕРє';
    final callIdStr = data['callId'];

    debugPrint('[APP] APP incoming push tap вЂ” callerId=$callerIdStr, callerName=$callerName, callId=$callIdStr');

    if (callerIdStr == null) {
      debugPrint('[APP] вљ пёЏ callerId is null, cannot process');
      return;
    }

    final callerId = int.tryParse(callerIdStr);
    if (callerId == null) {
      debugPrint('[APP] вљ пёЏ invalid callerId: $callerIdStr');
      return;
    }

    final callId = callIdStr != null ? int.tryParse(callIdStr) ?? 0 : 0;

    final callService = CallService();

    // Р•СЃР»Рё state СѓР¶Рµ RINGING вЂ” socket СѓР¶Рµ СѓСЃС‚Р°РЅРѕРІРёР» СЃРѕСЃС‚РѕСЏРЅРёРµ,
    // hydrate РЅРµ РЅСѓР¶РµРЅ. РџСЂРѕСЃС‚Рѕ РїРѕРєР°Р·С‹РІР°РµРј РґРёР°Р»РѕРі.
    if (callService.state == CallState.RINGING) {
      debugPrint('[APP] state=RINGING вЂ” showing dialog without hydrate');
      showIncomingCallDialogFromService(
        callerId: callerId,
        callerName: callerName,
        callId: callId,
        source: 'push',
      );
      return;
    }

    // Р•СЃР»Рё СѓР¶Рµ РЅР° Р·РІРѕРЅРєРµ (CALLING / IN_CALL) вЂ” РёРіРЅРѕСЂРёСЂСѓРµРј push
    if (callService.state == CallState.CALLING ||
        callService.state == CallState.IN_CALL) {
      debugPrint('[APP] вљ пёЏ already in call (state=${callService.state}) вЂ” ignoring push tap');
      return;
    }

    // Р’РѕСЃСЃС‚Р°РЅР°РІР»РёРІР°РµРј СЃРѕСЃС‚РѕСЏРЅРёРµ РёР· push
    debugPrint('[APP] Hydrating incoming call from push (state=${callService.state})');
    callService.hydrateIncomingCallFromPush(
      callId: callIdStr ?? '',
      callerId: callerIdStr,
      callerName: callerName,
    );

    showIncomingCallDialogFromService(
      callerId: callerId,
      callerName: callerName,
      callId: callId,
      source: 'push',
    );
  }


  /// РњРѕРЅРёС‚РѕСЂРёРЅРі РїРѕРґРєР»СЋС‡РµРЅРёСЏ Рє РёРЅС‚РµСЂРЅРµС‚Сѓ
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
    debugPrint('[APP_SHELL] _checkAuth() вЂ” BEGIN');
    try {
      final auth = context.read<AuthProvider>();
      debugPrint('[APP_SHELL] _checkAuth() вЂ” AuthProvider obtained');
      final hasToken = await auth.checkAuth();
      debugPrint('[APP_SHELL] _checkAuth() вЂ” checkAuth() returned: hasToken=$hasToken');

      if (!mounted) {
        debugPrint('[APP_SHELL] _checkAuth() вЂ” not mounted after checkAuth, returning');
        return;
      }

      if (hasToken) {
        if (auth.currentUser == null) {
          debugPrint('[APP_SHELL] _checkAuth() вЂ” hasToken but currentUser is null, showing LoginScreen');
          _currentScreen = const LoginScreen();
        } else {
          debugPrint('[APP_SHELL] _checkAuth() вЂ” authenticated as user: ${auth.currentUser?.id}, isAdmin=${auth.isAdmin}');
          // РџРѕСЃР»Рµ СѓСЃРїРµС€РЅРѕР№ Р°СѓС‚РµРЅС‚РёС„РёРєР°С†РёРё РѕС‚РїСЂР°РІР»СЏРµРј FCM token РЅР° backend
          debugPrint('[APP] token sync after auth begin');
          unawaited(PushService().syncTokenToBackend().then((_) {
            debugPrint('[APP] token sync after auth success');
          }).catchError((e) {
            debugPrint('[APP] token sync after auth fail: $e');
          }));

          // Р РµРЅРґРµСЂРёРј РЅСѓР¶РЅС‹Р№ СЌРєСЂР°РЅ РїСЂСЏРјРѕ Р·РґРµСЃСЊ, Р±РµР· pushReplacement
          _currentScreen = auth.isAdmin
              ? const AdminScreen()
              : const UserScreen();
        }
      } else {
        debugPrint('[APP_SHELL] _checkAuth() вЂ” no token, showing LoginScreen');
        _currentScreen = const LoginScreen();
      }

      debugPrint('[APP_SHELL] _checkAuth() вЂ” setting _isChecking=false, _currentScreen=$_currentScreen');
      setState(() {
        _isChecking = false;
      });
      debugPrint('[APP_SHELL] _checkAuth() вЂ” END');
    } catch (e, stack) {
      debugPrint('[APP_SHELL] рџ”ґ CRASH in _checkAuth: $e');
      debugPrint('[APP_SHELL] рџ”ґ StackTrace: $stack');
      // Fallback вЂ” РїРѕРєР°Р·С‹РІР°РµРј LoginScreen РїСЂРё РѕС€РёР±РєРµ
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
        // РћСЃРЅРѕРІРЅРѕР№ РєРѕРЅС‚РµРЅС‚ РїСЂРёР»РѕР¶РµРЅРёСЏ
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
              child: Text('РћС€РёР±РєР° Р·Р°РіСЂСѓР·РєРё РїСЂРёР»РѕР¶РµРЅРёСЏ'),
            ),
          ),
        // РџР»Р°С€РєР° "РќРµС‚ СЃРѕРµРґРёРЅРµРЅРёСЏ"
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
                        'РќРµС‚ СЃРѕРµРґРёРЅРµРЅРёСЏ СЃ СЃРµС‚СЊСЋ. РћР¶РёРґР°РЅРёРµ РІРѕСЃСЃС‚Р°РЅРѕРІР»РµРЅРёСЏ...',
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

  /// Р•РґРёРЅС‹Р№ РјРµС‚РѕРґ РѕС‚РєСЂС‹С‚РёСЏ CallScreen.
  /// Р’С‹Р·С‹РІР°РµС‚ markCallScreenOpen() Рё РґРµР»Р°РµС‚ Navigator.push.
  void _openCallScreen({
    required int userId,
    required String userName,
    required bool isIncoming,
    required String from,
  }) {
    final callService = CallService();
    callService.markCallScreenOpen();
    debugPrint('[APP] вњ… _openCallScreen вЂ” opening CallScreen (userId=$userId, from=$from)');
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
