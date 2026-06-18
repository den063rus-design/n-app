import 'dart:async';
import 'package:flutter/material.dart';
import '../app/app.dart';
import 'socket_service.dart';
import 'call_logger.dart';
import 'call_ringtone_service.dart';
import 'livekit_service.dart';
import 'call_session.dart';
import 'push_service.dart';

enum CallState {
  IDLE,
  CALLING,
  RINGING,
  /// Звонок принят (call:accept отправлен), но подключение к LiveKit ещё не завершено.
  /// Промежуточное состояние между RINGING и IN_CALL.
  /// Позволяет UI показать индикатор подключения вместо преждевременного IN_CALL.
  ACCEPTING,
  IN_CALL,
  ENDED,
}

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  final SocketService _socketService = SocketService();
  final CallLogger _callLogger = CallLogger();
  final LiveKitService _liveKitService = LiveKitService();

  /// Текущая сессия звонка (LiveKit).
  /// Создаётся в [connectToCall], уничтожается в [_endCall].
  CallSession? _currentSession;

  /// Публичный геттер для UI (CallScreen, ActiveCallOverlay).
  CallSession? get currentSession => _currentSession;

  // Состояние
  CallState _state = CallState.IDLE;
  int? _currentCallId;
  int? _remoteUserId;
  String? _remoteUserName;
  bool _isCameraOn = true;
  bool _isMicOn = true;
  bool _isFrontCamera = true;

  // Флаг: открыт ли экран звонка (для предотвращения дублей)
  bool _isCallScreenOpen = false;

  // Флаг: открыт ли диалог входящего звонка (для предотвращения дублей)
  bool _isIncomingDialogOpen = false;

  // Флаг: предотвращает повторный вызов acceptCall()
  bool _isAcceptingCall = false;

  // Флаг: свёрнут ли звонок в mini-call overlay
  bool _isMinimized = false;

  // Таймер отложенного сброса после завершения звонка
  Timer? _resetTimer;

  // StreamController для UI
  final _stateController = StreamController<CallState>.broadcast();

  // Стрим для оповещения о входящем звонке (глобальная навигация)
  final _incomingCallController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get incomingCallStream => _incomingCallController.stream;

  // Стрим для оповещения о сворачивании/разворачивании звонка
  final _minimizedController = StreamController<bool>.broadcast();
  Stream<bool> get minimizedStream => _minimizedController.stream;

  Stream<CallState> get stateStream => _stateController.stream;

  CallState get state => _state;
  bool get isCameraOn => _isCameraOn;
  bool get isMicOn => _isMicOn;
  int? get remoteUserId => _remoteUserId;
  String? get remoteUserName => _remoteUserName;
  int? get currentCallId => _currentCallId;
  bool get isMinimized => _isMinimized;
  bool get isIncomingDialogOpen => _isIncomingDialogOpen;

  String? _lastEndReason;
  String? get lastEndReason => _lastEndReason;

  /// Время завершения последнего звонка (millisecondsSinceEpoch).
  /// Используется в PushService для stale push guard.
  int? _lastCallEndTimestamp;
  int? get lastCallEndTimestamp => _lastCallEndTimestamp;

  // Подписка на стрим изменения подключения socket
  StreamSubscription<bool>? _connectionSubscription;

  // Подписки на CallSession
  VoidCallback? _sessionStateListener;
  VoidCallback? _sessionRemoteVideoListener;

  Future<void> init() async {
    _log('🔧 init()');
    await _requestPermissions();
    _socketService.setOnConnectCallback(_setupSocketListeners);

    // Принудительная регистрация listener-ов, если socket уже подключён
    if (_socketService.socket != null && _socketService.socket!.connected) {
      _log('[CallService] Socket already connected — registering listeners immediately');
      _setupSocketListeners();
    }

    // Подписываемся на изменения состояния подключения socket.
    _connectionSubscription = _socketService.onConnectionChanged.listen((connected) {
      if (connected) {
        _log('🔌 Socket reconnected — re-registering listeners');
        _setupSocketListeners();
      }
    });
  }

  /// Отмечает, что экран звонка открыт (предотвращает дубли)
  void markCallScreenOpen() => _isCallScreenOpen = true;

  /// Отмечает, что экран звонка закрыт
  void markCallScreenClosed() => _isCallScreenOpen = false;

  /// Проверяет, открыт ли уже экран звонка
  bool get isCallScreenOpen => _isCallScreenOpen;

  /// Отмечает, что диалог входящего звонка открыт
  void markIncomingDialogOpen() => _isIncomingDialogOpen = true;

  /// Отмечает, что диалог входящего звонка закрыт
  void markIncomingDialogClosed() => _isIncomingDialogOpen = false;

  /// Сворачивает звонок в mini-call overlay
  void minimizeCall() {
    if (_state == CallState.CALLING ||
        _state == CallState.RINGING ||
        _state == CallState.IN_CALL) {
      _isMinimized = true;
      _minimizedController.add(_isMinimized);
      _log('📱 minimizeCall() — call minimized, isMinimized=true');
    } else {
      _log('⚠️ minimizeCall() — cannot minimize in state=$_state');
    }
  }

  /// Разворачивает звонок из mini-call overlay в fullscreen
  void expandCall() {
    _isMinimized = false;
    _minimizedController.add(_isMinimized);
    _log('📱 expandCall() — call expanded, isMinimized=false');
  }

  /// Восстанавливает состояние входящего звонка из push-уведомления.
  void hydrateIncomingCallFromPush({
    required String callId,
    required String callerId,
    required String callerName,
  }) {
    _log('📞 hydrateIncomingCallFromPush() — callId=$callId, callerId=$callerId, callerName=$callerName');

    final parsedCallId = int.tryParse(callId);
    final parsedCallerId = int.tryParse(callerId);

    if (parsedCallId == null || parsedCallerId == null) {
      _log('⚠️ hydrateIncomingCallFromPush — failed to parse callId or callerId, ignoring');
      return;
    }

    if (_state == CallState.CALLING ||
        _state == CallState.RINGING ||
        _state == CallState.IN_CALL) {
      _log('⚠️ hydrateIncomingCallFromPush — already in call, state=$_state, ignoring');
      return;
    }

    _resetTimer?.cancel();
    _hardReset();

    _state = CallState.RINGING;
    _currentCallId = parsedCallId;
    _remoteUserId = parsedCallerId;
    _remoteUserName = callerName;
    _stateController.add(_state);
    _log('✅ hydrateIncomingCallFromPush — state set to RINGING');
  }

  Future<void> _requestPermissions() async {
    // Разрешения запрашиваются централизованно в AppPermissionsService при старте.
  }

  void _setupSocketListeners() {
    _log('🔌 _setupSocketListeners begin');

    final socket = _socketService.socket;
    if (socket == null) {
      _log('🔌 _setupSocketListeners — socket is NULL');
      return;
    }

    // Убираем guard _listenersAttached — socket.off() + socket.on() идемпотентны.
    // После reconnect socket.io создаёт новый объект socket, и listener-ы
    // на старом объекте не переносятся. Поэтому всегда перерегистрируем.
    _log('🔌 _setupSocketListeners — registering listeners (idempotent)');

    // Всегда отписываемся перед подпиской, чтобы избежать дублирования
    socket.off('call:incoming');
    socket.off('call:accepted');
    socket.off('call:ended');
    socket.off('call:rejected');

    _log('🔌 _setupSocketListeners — registering: call:incoming');

    _socketService.onCallEvent('call:incoming', (data) {
      _log('📞 call:incoming RECEIVED — data: $data, state=$_state');

      // Единственный guard на транспортном уровне:
      // если уже на звонке — игнорируем входящий
      if (_state == CallState.CALLING ||
          _state == CallState.RINGING ||
          _state == CallState.IN_CALL) {
        _log('📞 call:incoming ignored because state=$_state');
        return;
      }

      // Сбрасываем состояние и устанавливаем RINGING
      _resetTimer?.cancel();
      _hardReset();
      _state = CallState.RINGING;
      _currentCallId = data['callId'];
      _remoteUserId = data['callerId'];
      _remoteUserName = data['callerName'] ?? 'Пользователь';
      _stateController.add(_state);
      _log('✅ call:incoming processed — callId=$_currentCallId, callerId=$_remoteUserId');

      // Доставляем событие в UI-слой (app.dart).
      // UI-слой сам решает, показывать диалог или нет.
      _incomingCallController.add({
        'callId': data['callId'],
        'callerId': data['callerId'],
        'callerName': data['callerName'] ?? 'Пользователь',
      });
    });

    _socketService.onCallEvent('call:accepted', (data) async {
      final callerSw = Stopwatch()..start();
      _log('📞 CALL_SERVICE call:accepted received callId=${data['callId']}, state=$_state');

      await CallRingtoneService().stopAllCallSounds();

      if (_currentCallId == null && data['callId'] != null) {
        _currentCallId = data['callId'];
      }

      _log('📞 CALL_SERVICE caller _currentCallId before connect=$_currentCallId');

      // Подключаемся к LiveKit комнате
      if (_currentCallId != null) {
        _log('📞 CALL_SERVICE caller connecting to LiveKit callId=$_currentCallId');

        _log('[CALLER_FLOW] connect start callId=$_currentCallId state=$_state elapsedMs=${callerSw.elapsedMilliseconds}');

        try {
          await connectToCall(_currentCallId!);
          _log('[CALLER_FLOW] connect success callId=$_currentCallId sessionState=${_currentSession?.connectionState.value} elapsedMs=${callerSw.elapsedMilliseconds}');
          _log('📞 CALL_SERVICE caller connectToCall finished');

          // Проверка: LiveKit действительно подключился
          if (_currentSession == null ||
              _currentSession!.connectionState.value != LiveKitConnectionState.connected) {
            _log('🔴 CALL_SERVICE caller LiveKit not connected after connect state=${_currentSession?.connectionState.value}');
            throw StateError('LiveKit did not reach connected state for callId=$_currentCallId');
          }
          _log('[CALLER_FLOW] connected confirmed callId=$_currentCallId elapsedMs=${callerSw.elapsedMilliseconds}');

          // Только после успешного connectToCall переходим в IN_CALL
          _log('[CALLER_FLOW] setting IN_CALL callId=$_currentCallId');
          _state = CallState.IN_CALL;
          _stateController.add(_state);

          _setupLiveKitListeners();
          _log('[CALLER_FLOW] caller success callId=$_currentCallId finalState=$_state totalElapsedMs=${callerSw.elapsedMilliseconds}');
        } catch (e) {
          _log('[CALLER_FLOW] connect fail callId=$_currentCallId error=$e elapsedMs=${callerSw.elapsedMilliseconds}');
          // Блок 3: StateError('already connecting') — не фатальная ошибка,
          // это дублирующий вызов connectToCall. Не отправляем call:end.
          if (e is StateError && e.message.contains('already connecting')) {
            _log('[CALLER_FLOW] ⚠️ duplicate connect detected — not ending call callId=$_currentCallId');
            return;
          }
          // Диагностика: проверяем, был ли отправлен HTTP-запрос на /livekit/token
          if (_currentSession?.isLiveKitTokenRequested == true) {
            _log('[CALL_END_BEFORE_TOKEN] 🔴 CALLER: call:end will be sent while HTTP token request is in flight! callId=$_currentCallId');
          }
          _log(' CALL_SERVICE caller sending call:end because connect failed callId=$_currentCallId');
          // Уведомляем backend о завершении звонка, чтобы не блокировать последующие
          if (_currentCallId != null) {
            _socketService.sendCallEvent('call:end', {
              'callId': _currentCallId,
              'reason': 'connect_failed',
            });
          }
          _log('END_SOURCE=caller_call_accepted_catch callId=$_currentCallId');
          _endCall(reason: 'connection_failed');
        }
      } else {
        _log('⚠️ CALL_SERVICE call:accepted but _currentCallId is null');
      }
      callerSw.stop();
    });

    _socketService.onCallEvent('call:ended', (data) {
      _log('📞 call:ended — data: $data, state=$_state');

      if (_state == CallState.IDLE || _state == CallState.ENDED) {
        _log('📞 call:ended — already in state=$_state, skipping');
        return;
      }

      CallRingtoneService().stopAllCallSounds();

      final reason = data['reason'] as String?;
      _log('END_SOURCE=socket_call_ended callId=$_currentCallId reason=$reason');
      _endCall(reason: reason);
      if (reason == 'rejected') {
        _showSnackbar('Звонок отклонён');
      } else if (reason == 'expired') {
        _showSnackbar('Звонок уже завершён');
      }
    });

    _socketService.onCallEvent('call:rejected', (data) {
      _log('📞 call:rejected — data: $data, state=$_state');
      if (_state == CallState.CALLING || _state == CallState.RINGING) {
        CallRingtoneService().stopAllCallSounds();
        _endCall(reason: 'rejected');
      } else {
        _log('📞 call:rejected — ignored, state=$_state');
      }
    });

    _log('🔌 _setupSocketListeners() — ✅ listeners registered');
  }

  /// Подключается к LiveKit через [CallSession].
  ///
  /// Создаёт новый [CallSession] через [LiveKitService.createSession],
  /// вызывает [CallSession.connect()] и сохраняет сессию в [_currentSession].
  Future<void> connectToCall(int callId) async {
    _log('📞 CALL_SERVICE connectToCall callId=$callId');

    // Уничтожаем предыдущую сессию, если есть
    if (_currentSession != null) {
      _log('📞 CALL_SERVICE disposing previous session before new connect');
      await _currentSession!.disconnect();
      _currentSession!.dispose();
      _currentSession = null;
    }

    final session = _liveKitService.createSession(callId);
    _currentSession = session;

    try {
      await session.connect();
    } catch (e) {
      _log('🔴 CALL_SERVICE connectToCall failed callId=$callId error=$e');
      // Если connect упал, session уже выставил connectionState=error
      // Не чистим _currentSession здесь — _endCall сделает cleanup
      rethrow;
    }
  }

  /// Подписывается на изменения состояния [CallSession] для синхронизации с CallService.
  void _setupLiveKitListeners() {
    final session = _currentSession;
    if (session == null) {
      _log('⚠️ _setupLiveKitListeners — _currentSession is null');
      return;
    }

    // Защита от дублирования: отписываемся от старых listener-ов перед подпиской
    if (_sessionRemoteVideoListener != null) {
      session.remoteVideoTrack.removeListener(_sessionRemoteVideoListener!);
    }
    if (_sessionStateListener != null) {
      session.connectionState.removeListener(_sessionStateListener!);
    }

    // Слушаем изменения remote video track для обновления стримов
    _sessionRemoteVideoListener = () {
      final hasRemoteVideo = session.remoteVideoTrack.value != null;
      _log('📹 LiveKit remote video track changed: ${hasRemoteVideo ? "PRESENT" : "null"}');
    };
    session.remoteVideoTrack.addListener(_sessionRemoteVideoListener!);

    // Слушаем состояние подключения
    _sessionStateListener = () {
      final connState = session.connectionState.value;
      _log('🔌 LiveKit connection state changed: $connState (call state=$_state)');
      // Блок 3: disconnected срабатывает только при реальном активном разговоре (IN_CALL).
      // ACCEPTING и CALLING — переходные состояния, disconnected в них может быть
      // частью handshake (например, RoomDisconnectedEvent при переподключении).
      if (connState == LiveKitConnectionState.disconnected &&
          _state == CallState.IN_CALL) {
        _log('🔴 LiveKit disconnected during active call');
        _log('END_SOURCE=livekit_disconnected_listener callId=$_currentCallId state=$_state');
        _endCall(reason: 'peer_disconnected');
      }
    };
    session.connectionState.addListener(_sessionStateListener!);
  }

  Future<void> startCall(int userId) async {
    _log('📞 startCall() — userId=$userId, state=$_state');

    _resetTimer?.cancel();
    _lastEndReason = null;
    _lastCallEndTimestamp = null;

    if (_state != CallState.IDLE) {
      _log('⚠️ startCall() — state=$_state, forcing hard reset');
      _hardReset();
    }

    _isMinimized = false;
    _minimizedController.add(false);

    await _callLogger.init();

    _state = CallState.CALLING;
    _remoteUserId = userId;
    _stateController.add(_state);

    _socketService.sendCallEvent('call:start', {
      'calleeId': userId,
    });
    _log('📞 call:start sent, waiting for call:accepted...');

    await CallRingtoneService().playOutgoingRingbackTone();
  }

  Future<void> acceptCall() async {
    final acceptSw = Stopwatch()..start();
    _log('[ACCEPT_FLOW] begin callId=$_currentCallId state=$_state');

    // Защита от повторного вызова acceptCall()
    if (_isAcceptingCall) {
      _log('⚠️ CALL_SERVICE acceptCall skipped — already accepting');
      return;
    }
    _isAcceptingCall = true;

    try {
      await CallRingtoneService().stopAllCallSounds();
      await PushService().cancelIncomingCallNotification();
      _resetTimer?.cancel();

      if (_currentCallId == null) {
        _log('⚠️ CALL_SERVICE acceptCall — _currentCallId is NULL');
        return;
      }

      final callId = _currentCallId;

      _socketService.sendCallEvent('call:accept', {
        'callId': callId,
      });
      _log('📞 CALL_SERVICE call:accept sent callId=$callId elapsedMs=${acceptSw.elapsedMilliseconds}');

      // НЕ ставим IN_CALL до успешного подключения к LiveKit.
      // Оставляем RINGING (или IDLE), чтобы UI не переключался преждевременно.
      // Устанавливаем ACCEPTING — UI может показать индикатор подключения
      _log('[ACCEPT_FLOW] setting ACCEPTING callId=$callId');
      _state = CallState.ACCEPTING;
      _stateController.add(_state);

      _log('📞 CALL_SERVICE callee connecting to LiveKit callId=$callId');

      _log('[ACCEPT_FLOW] connect start callId=$callId state=$_state elapsedMs=${acceptSw.elapsedMilliseconds}');

      try {
        await connectToCall(callId!);
        _log('[ACCEPT_FLOW] connect success callId=$callId sessionState=${_currentSession?.connectionState.value} elapsedMs=${acceptSw.elapsedMilliseconds}');
        _log('📞 CALL_SERVICE callee connectToCall finished');

        // Проверка: LiveKit действительно подключился
        if (_currentSession == null ||
            _currentSession!.connectionState.value != LiveKitConnectionState.connected) {
          _log('🔴 CALL_SERVICE callee LiveKit not connected after connect state=${_currentSession?.connectionState.value}');
          throw StateError('LiveKit did not reach connected state for callId=$callId');
        }
        _log('[ACCEPT_FLOW] connected confirmed callId=$callId elapsedMs=${acceptSw.elapsedMilliseconds}');

        // Только после успешного connectToCall переходим в IN_CALL
        _log('[ACCEPT_FLOW] setting IN_CALL callId=$callId');
        _state = CallState.IN_CALL;
        _stateController.add(_state);
        _log('📞 CALL_SERVICE callee state set to IN_CALL');

        _setupLiveKitListeners();
        _log('[ACCEPT_FLOW] acceptCall success callId=$callId finalState=$_state totalElapsedMs=${acceptSw.elapsedMilliseconds}');
      } catch (e) {
        _log('[ACCEPT_FLOW] connect fail callId=$callId error=$e elapsedMs=${acceptSw.elapsedMilliseconds}');
        // Блок 3: StateError('already connecting') — не фатальная ошибка,
        // это дублирующий вызов connectToCall. Не отправляем call:end.
        if (e is StateError && e.message.contains('already connecting')) {
          _log('[ACCEPT_FLOW] ⚠️ duplicate connect detected — not ending call callId=$callId');
          return;
        }
        // Диагностика: проверяем, был ли отправлен HTTP-запрос на /livekit/token
        if (_currentSession?.isLiveKitTokenRequested == true) {
          _log('[CALL_END_BEFORE_TOKEN] 🔴 CALLEE: call:end will be sent while HTTP token request is in flight! callId=$callId');
        }
        _log(' CALL_SERVICE sending call:end because connect failed callId=$callId');
        // Уведомляем backend о завершении звонка, чтобы не блокировать последующие
        if (callId != null) {
          _socketService.sendCallEvent('call:end', {
            'callId': callId,
            'reason': 'connect_failed',
          });
        }
        _log('END_SOURCE=acceptCall_catch callId=$callId');
        _endCall(reason: 'connection_failed');
        // Пробрасываем исключение наверх, чтобы app.dart знал, что accept не удался
        rethrow;
      }
    } finally {
      _isAcceptingCall = false;
      acceptSw.stop();
    }
  }

  Future<void> rejectCall() async {
    _log('❌ rejectCall() — callId=$_currentCallId, state=$_state');

    await CallRingtoneService().stopAllCallSounds();
    await PushService().cancelIncomingCallNotification();

    if (_currentCallId == null) {
      _log('⚠️ rejectCall() — _currentCallId is NULL');
    }
    _socketService.sendCallEvent('call:reject', {
      'callId': _currentCallId,
    });
    _log('❌ call:reject sent');
    _endCall(reason: 'rejected');
  }

  Future<void> endCall() async {
    _log('🔴 endCall() — callId=$_currentCallId, state=$_state');

    // Отключаемся от LiveKit через сессию
    if (_currentSession != null) {
      await _currentSession!.disconnect();
    }

    if (_currentCallId != null) {
      _socketService.sendCallEvent('call:end', {
        'callId': _currentCallId,
      });
    } else {
      _log('🔴 endCall() — no active call, skipping socket event');
    }

    _log('END_SOURCE=manual_endCall callId=$_currentCallId');
    _endCall();
  }

  void toggleCamera() {
    _isFrontCamera = !_isFrontCamera;
    _currentSession?.switchCamera();
  }

  void toggleMic() {
    _isMicOn = !_isMicOn;
    _currentSession?.setMicrophoneEnabled(_isMicOn);
  }

  void toggleCameraVideo() {
    _isCameraOn = !_isCameraOn;
    _currentSession?.setCameraEnabled(_isCameraOn);
  }

  void _showSnackbar(String message) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  void handleConnectionLost() {
    if (_state == CallState.CALLING ||
        _state == CallState.RINGING ||
        _state == CallState.IN_CALL) {
      _log('END_SOURCE=handleConnectionLost callId=$_currentCallId state=$_state');
      _endCall(reason: 'peer_disconnected');
    }
  }

  Future<void> _endCall({String? reason}) async {
    _log('🔴 _endCall() ENTER reason=$reason state=$_state callId=$_currentCallId');
    if (_state == CallState.ENDED || _state == CallState.IDLE) {
      _log('🔴 _endCall() — already in state=$_state, skipping');
      return;
    }

    // Защита от гонки: если HTTP-запрос на /livekit/token ещё в полёте,
    // ждём до 2 секунд, чтобы он завершился, прежде чем отправлять call:end.
    // Это предотвращает ситуацию, когда call:end (Socket.IO) приходит на backend
    // раньше, чем POST /livekit/token (HTTP), и backend возвращает 400.
    if (_currentSession?.isLiveKitTokenRequested == true) {
      _log('[CALL_END_BEFORE_TOKEN] ⚠️ _endCall called while HTTP token request is in flight! reason=$reason');
      _log('[CALL_END_BEFORE_TOKEN] ⚠️ Waiting up to 2s for token request to complete...');
      try {
        await Future.any([
          // Ждём, пока isLiveKitTokenRequested станет false
          (() async {
            while (_currentSession?.isLiveKitTokenRequested == true) {
              await Future.delayed(const Duration(milliseconds: 100));
            }
          })(),
          // Или таймаут 2 секунды
          Future.delayed(const Duration(seconds: 2)),
        ]);
        _log('[CALL_END_BEFORE_TOKEN] ✅ Token request completed (or timed out), proceeding with call:end');
      } catch (e) {
        _log('[CALL_END_BEFORE_TOKEN] ⚠️ Error while waiting for token: $e');
      }
    }

    _log('🔴 _endCall() — reason=$reason, state=$_state');

    // Отключаем LiveKit через сессию
    if (_currentSession != null) {
      await _currentSession!.disconnect();
    }

    // Отписываемся от CallSession listeners
    final session = _currentSession;
    if (session != null) {
      if (_sessionRemoteVideoListener != null) {
        session.remoteVideoTrack.removeListener(_sessionRemoteVideoListener!);
        _sessionRemoteVideoListener = null;
      }
      if (_sessionStateListener != null) {
        session.connectionState.removeListener(_sessionStateListener!);
        _sessionStateListener = null;
      }
    }

    // Уничтожаем сессию
    _currentSession?.dispose();
    _currentSession = null;

    _lastEndReason = reason;
    _lastCallEndTimestamp = DateTime.now().millisecondsSinceEpoch;

    await CallRingtoneService().stopAllCallSounds();
    await PushService().cancelIncomingCallNotification();

    _state = CallState.ENDED;
    _stateController.add(_state);
    _isMinimized = false;
    _isCallScreenOpen = false;
    _isIncomingDialogOpen = false;
    _log('✅ _endCall() — state=ENDED');
    _callLogger.close();
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 2000), () {
      _hardReset();
    });
  }

  /// Полный сброс ВСЕГО состояния звонка.
  void _hardReset() {
    _log('🔄 _hardReset()');

    CallRingtoneService().stopAllCallSounds();

    // Блок 4: Очищаем сессию и её listeners
    if (_currentSession != null) {
      _log('🔄 _hardReset() — cleaning up session callId=$_currentCallId');
      // Отписываемся от CallSession listeners
      if (_sessionRemoteVideoListener != null) {
        _currentSession!.remoteVideoTrack.removeListener(_sessionRemoteVideoListener!);
        _sessionRemoteVideoListener = null;
      }
      if (_sessionStateListener != null) {
        _currentSession!.connectionState.removeListener(_sessionStateListener!);
        _sessionStateListener = null;
      }
      _currentSession!.dispose();
      _currentSession = null;
    }

    _lastCallEndTimestamp = DateTime.now().millisecondsSinceEpoch;

    _state = CallState.IDLE;
    _currentCallId = null;
    _remoteUserId = null;
    _remoteUserName = null;
    _isCameraOn = true;
    _isMicOn = true;
    _isFrontCamera = true;
    _isIncomingDialogOpen = false;
    _isCallScreenOpen = false;
    _isMinimized = false;
    _isAcceptingCall = false;
    _lastEndReason = null;
    _stateController.add(CallState.IDLE);
  }

  /// Публичный метод полного сброса состояния звонка.
  void hardReset() {
    _hardReset();
  }

  void dispose() {
    _connectionSubscription?.cancel();
    _stateController.close();
    _incomingCallController.close();
    _minimizedController.close();
  }

  /// Пишет лог одновременно в print (adb) и в файл (CallLogger)
  void _log(String message) {
    print('[CALL_SERVICE] $message');
    _callLogger.log('CallService', message);
  }
}
