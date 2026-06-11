import 'dart:async';
import 'package:flutter/foundation.dart';
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
import '../screens/call_screen.dart';
import '../screens/login_screen.dart';
import '../screens/admin_screen.dart';
import '../screens/user_screen.dart';
import '../screens/notifications_screen.dart';

/// Глобальный ключ навигатора для доступа из CallService
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
      ),
    );
  }
}

/// Корневая обёртка: immersive mode + мониторинг сети
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> with WidgetsBindingObserver {
  bool _isChecking = true;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enableStandardSystemUi();
    _checkAuth();
    _monitorConnectivity();
    // Осознанный unawaited: инициализация CallService не должна блокировать
    // отрисовку первого экрана. Это безопасно, потому что:
    // 1. _setupSocketListeners() защищён флагом _listenersAttached
    // 2. _listenIncomingCalls() подписывается на пустой стрим —
    //    данные появятся только после реального call:incoming от сервера
    // 3. _requestPermissions() не влияет на логику звонков
    unawaited(_initServices());
    _listenIncomingCalls();
  }

  /// Инициализирует глобальные сервисы (CallService).
  Future<void> _initServices() async {
    await CallService().init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingCallSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enableStandardSystemUi();
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

  /// Слушает входящие звонки и автоматически открывает CallScreen
  void _listenIncomingCalls() {
    final callService = CallService();
    _incomingCallSubscription = callService.incomingCallStream.listen((data) {
      if (!mounted) return;

      final callerId = data['callerId'] as int;
      final callerName = data['callerName'] as String;

      // Проверяем, что звонок действительно в статусе RINGING
      // (защита от дублей: если уже IN_CALL или IDLE — не открываем)
      if (callService.state != CallState.RINGING) return;

      // Проверяем, не открыт ли уже экран звонка (через флаг)
      if (callService.isCallScreenOpen) return;

      // Отмечаем, что экран будет открыт
      callService.markCallScreenOpen();

      Navigator.push(
        navigatorKey.currentContext!,
        MaterialPageRoute(
          settings: const RouteSettings(name: 'call_screen'),
          builder: (context) => CallScreen(
            userId: callerId,
            userName: callerName,
            isIncoming: true,
          ),
        ),
      );
    });
  }

  /// Мониторинг подключения к интернету
  void _monitorConnectivity() {
    Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      // results — это List<ConnectivityResult>
      final hasConnection = results.any((r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet);

      setState(() {
        _isOffline = !hasConnection;
      });
    });
  }

  Future<void> _checkAuth() async {
    final auth = context.read<AuthProvider>();
    final hasToken = await auth.checkAuth();

    if (!mounted) return;

    if (hasToken) {
      if (auth.currentUser == null) {
        Navigator.pushReplacementNamed(context, '/login');
      } else {
        Navigator.pushReplacementNamed(
          context,
          auth.isAdmin ? '/admin' : '/user',
        );
      }
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }

    setState(() {
      _isChecking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_isChecking)
          const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          )
        else
          const SizedBox.shrink(),
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
}
