import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../app/app.dart';
import 'socket_service.dart';
import 'call_logger.dart';
import 'call_ringtone_service.dart';
import 'livekit_service.dart';

enum CallState {
  IDLE,
  CALLING,
  RINGING,
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

  // WebRTC — оставляем поля для обратной совместимости,
  // но в новом LiveKit flow они не используются
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

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
  final _localStreamController = StreamController<MediaStream?>.broadcast();
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();

  // Стрим для оповещения о входящем звонке (глобальная навигация)
  final _incomingCallController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get incomingCallStream => _incomingCallController.stream;

  // Стрим для оповещения о сворачивании/разворачивании звонка
  final _minimizedController = StreamController<bool>.broadcast();
  Stream<bool> get minimizedStream => _minimizedController.stream;

  Stream<CallState> get stateStream => _stateController.stream;
  Stream<MediaStream?> get localStream => _localStreamController.stream;
  Stream<MediaStream?> get remoteStream => _remoteStreamController.stream;

  /// Текущий локальный MediaStream (может быть null, если звонок не начат).
  /// Нужен для немедленного назначения в renderer без ожидания stream-события.
  MediaStream? get currentLocalStream => _localStream;

  /// Текущий удалённый MediaStream (может быть null, если remote peer не подключился).
  /// Нужен для немедленного назначения в renderer без ожидания stream-события.
  MediaStream? get currentRemoteStream => _remoteStream;

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

  // Подписки на LiveKitService
  VoidCallback? _liveKitStateListener;
  VoidCallback? _liveKitRemoteVideoListener;

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
    socket.off('call:signal');
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
      _log('📞 CALL_SERVICE call:accepted received callId=${data['callId']}, state=$_state');

      await CallRingtoneService().stopAllCallSounds();

      if (_currentCallId == null && data['callId'] != null) {
        _currentCallId = data['callId'];
      }

      _log('📞 CALL_SERVICE caller _currentCallId before connect=$_currentCallId');

      // Подключаемся к LiveKit комнате
      if (_currentCallId != null) {
        _log('📞 CALL_SERVICE caller connecting to LiveKit callId=$_currentCallId');

        _log('[CALLER_FLOW] before connectToCall callId=$_currentCallId state=$_state livekitState=${_liveKitService.connectionState.value}');

        try {
          await _liveKitService.connectToCall(_currentCallId!);
          _log('[CALLER_FLOW] after connectToCall callId=$_currentCallId livekitState=${_liveKitService.connectionState.value}');
          _log('📞 CALL_SERVICE caller connectToCall finished');

          // Проверка: LiveKit действительно подключился
          if (_liveKitService.connectionState.value != LiveKitConnectionState.connected) {
            _log('🔴 CALL_SERVICE caller LiveKit not connected after connect state=${_liveKitService.connectionState.value}');
            throw StateError('LiveKit did not reach connected state for callId=$_currentCallId');
          }
          _log('[CALLER_FLOW] connected confirmed callId=$_currentCallId');

          // Только после успешного connectToCall переходим в IN_CALL
          _log('[CALLER_FLOW] setting IN_CALL callId=$_currentCallId');
          _state = CallState.IN_CALL;
          _stateController.add(_state);

          _setupLiveKitListeners();
          _log('[CALLER_FLOW] caller success callId=$_currentCallId finalState=$_state');
        } catch (e) {
          _log('🔴 CALL_SERVICE caller connect failure callId=$_currentCallId state=$_state error=$e');
          _log('📤 CALL_SERVICE caller sending call:end because connect failed callId=$_currentCallId');
          // Уведомляем backend о завершении звонка, чтобы не блокировать последующие
          if (_currentCallId != null) {
            _socketService.sendCallEvent('call:end', {
              'callId': _currentCallId,
            });
          }
          _endCall(reason: 'connection_failed');
        }
      } else {
        _log('⚠️ CALL_SERVICE call:accepted but _currentCallId is null');
      }
    });

    // call:signal — legacy обработчик старого WebRTC signaling.
    // В новом LiveKit flow НЕ ИСПОЛЬЗУЕТСЯ.
    // Оставлен только для обратной совместимости со старыми клиентами.
    // Не запускает LiveKit, не меняет состояние нового звонка.
    _socketService.onCallEvent('call:signal', (data) async {
      _log('📡 call:signal — type=${data['type']}, state=$_state (IGNORED in LiveKit flow)');

      if (data['callId'] != null && data['callId'] != _currentCallId) {
        _log('📡 call:signal — ignoring signal for different call: ${data['callId']}');
        return;
      }

      // В новом LiveKit flow offer/answer/candidate полностью игнорируются.
      // Старый WebRTC-код оставлен только для legacy-клиентов.
      if (data['type'] == 'candidate') {
        if (_peerConnection != null) {
          try {
            await _peerConnection!.addCandidate(
              RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              ),
            );
          } catch (e) {
            _log('❌ ICE candidate add FAILED: $e');
          }
        } else {
          _log('⚠️ ICE candidate received but _peerConnection is NULL');
        }
      } else if (data['type'] == 'offer') {
        _log('📄 Offer received — IGNORED in LiveKit flow (legacy only)');
      } else if (data['type'] == 'answer') {
        _log('📄 Answer received — IGNORED in LiveKit flow (legacy only)');
        if (_peerConnection != null) {
          try {
            await _peerConnection!.setRemoteDescription(
              RTCSessionDescription(data['sdp'], data['type']),
            );
          } catch (e) {
            _log('❌ setRemoteDescription(answer) FAILED: $e');
          }
        } else {
          _log('⚠️ Answer received but _peerConnection is NULL');
        }
      } else {
        _log('⚠️ call:signal — unknown type: ${data['type']}');
      }
    });

    _socketService.onCallEvent('call:ended', (data) {
      _log('📞 call:ended — data: $data, state=$_state');

      if (_state == CallState.IDLE || _state == CallState.ENDED) {
        _log('📞 call:ended — already in state=$_state, skipping');
        return;
      }

      CallRingtoneService().stopAllCallSounds();

      final reason = data['reason'] as String?;
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

  /// Подписывается на изменения состояния LiveKit для синхронизации с CallService.
  void _setupLiveKitListeners() {
    // Защита от дублирования: отписываемся от старых listener-ов перед подпиской
    if (_liveKitRemoteVideoListener != null) {
      _liveKitService.remoteVideoTrack.removeListener(_liveKitRemoteVideoListener!);
    }
    if (_liveKitStateListener != null) {
      _liveKitService.connectionState.removeListener(_liveKitStateListener!);
    }

    // Слушаем изменения remote video track для обновления стримов
    _liveKitRemoteVideoListener = () {
      final hasRemoteVideo = _liveKitService.remoteVideoTrack.value != null;
      _log('📹 LiveKit remote video track changed: ${hasRemoteVideo ? "PRESENT" : "null"}');
    };
    _liveKitService.remoteVideoTrack.addListener(_liveKitRemoteVideoListener!);

    // Слушаем состояние подключения
    _liveKitStateListener = () {
      final connState = _liveKitService.connectionState.value;
      _log('🔌 LiveKit connection state changed: $connState (call state=$_state)');
      if (connState == LiveKitConnectionState.disconnected &&
          (_state == CallState.IN_CALL || _state == CallState.CALLING)) {
        _log('🔴 LiveKit disconnected during active call');
        _endCall(reason: 'peer_disconnected');
      }
    };
    _liveKitService.connectionState.addListener(_liveKitStateListener!);
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
    _log('📞 CALL_SERVICE acceptCall begin currentCallId=$_currentCallId, state=$_state');

    // Защита от повторного вызова acceptCall()
    if (_isAcceptingCall) {
      _log('⚠️ CALL_SERVICE acceptCall skipped — already accepting');
      return;
    }
    _isAcceptingCall = true;

    try {
      await CallRingtoneService().stopAllCallSounds();
      _resetTimer?.cancel();

      if (_currentCallId == null) {
        _log('⚠️ CALL_SERVICE acceptCall — _currentCallId is NULL');
        return;
      }

      final callId = _currentCallId;

      _socketService.sendCallEvent('call:accept', {
        'callId': callId,
      });
      _log('📞 CALL_SERVICE call:accept sent callId=$callId');

      // НЕ ставим IN_CALL до успешного подключения к LiveKit.
      // Оставляем RINGING (или IDLE), чтобы UI не переключался преждевременно.
      _log('📞 CALL_SERVICE callee connecting to LiveKit callId=$callId');

      _log('[ACCEPT_FLOW] before connectToCall callId=$callId state=$_state livekitState=${_liveKitService.connectionState.value}');

      try {
        await _liveKitService.connectToCall(callId!);
        _log('[ACCEPT_FLOW] after connectToCall callId=$callId livekitState=${_liveKitService.connectionState.value}');
        _log('📞 CALL_SERVICE callee connectToCall finished');

        // Проверка: LiveKit действительно подключился
        if (_liveKitService.connectionState.value != LiveKitConnectionState.connected) {
          _log('🔴 CALL_SERVICE callee LiveKit not connected after connect state=${_liveKitService.connectionState.value}');
          throw StateError('LiveKit did not reach connected state for callId=$callId');
        }
        _log('[ACCEPT_FLOW] connected confirmed callId=$callId');

        // Только после успешного connectToCall переходим в IN_CALL
        _log('[ACCEPT_FLOW] setting IN_CALL callId=$callId');
        _state = CallState.IN_CALL;
        _stateController.add(_state);
        _log('📞 CALL_SERVICE callee state set to IN_CALL');

        _setupLiveKitListeners();
        _log('[ACCEPT_FLOW] acceptCall success callId=$callId finalState=$_state');
      } catch (e) {
        _log('🔴 CALL_SERVICE acceptCall connect failure callId=$callId state=$_state error=$e');
        _log('📤 CALL_SERVICE sending call:end because connect failed callId=$callId');
        // Уведомляем backend о завершении звонка, чтобы не блокировать последующие
        if (callId != null) {
          _socketService.sendCallEvent('call:end', {
            'callId': callId,
          });
        }
        _endCall(reason: 'connection_failed');
        // Пробрасываем исключение наверх, чтобы app.dart знал, что accept не удался
        rethrow;
      }
    } finally {
      _isAcceptingCall = false;
    }
  }

  Future<void> rejectCall() async {
    _log('❌ rejectCall() — callId=$_currentCallId, state=$_state');

    await CallRingtoneService().stopAllCallSounds();

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

    // Отключаемся от LiveKit
    await _liveKitService.disconnect();

    if (_currentCallId != null) {
      _socketService.sendCallEvent('call:end', {
        'callId': _currentCallId,
      });
    } else {
      _log('🔴 endCall() — no active call, skipping socket event');
    }

    _endCall();
  }

  void toggleCamera() {
    _isFrontCamera = !_isFrontCamera;
    _liveKitService.switchCamera();
  }

  void toggleMic() {
    _isMicOn = !_isMicOn;
    _liveKitService.setMicrophoneEnabled(_isMicOn);
  }

  void toggleCameraVideo() {
    _isCameraOn = !_isCameraOn;
    _liveKitService.setCameraEnabled(_isCameraOn);
  }

  void _showSnackbar(String message) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  void _disposePeerResources() {
    try {
      _peerConnection?.onIceCandidate = null;
      _peerConnection?.onTrack = null;
      _peerConnection?.onConnectionState = null;
      _peerConnection?.onIceConnectionState = null;
      _peerConnection?.close();
    } catch (e) {
      _log('peer cleanup failed: $e');
    }

    _peerConnection = null;

    try {
      _localStream?.getTracks().forEach((track) => track.stop());
    } catch (e) {
      _log('local stream cleanup failed: $e');
    }

    _localStream = null;
    _remoteStream = null;
  }

  void handleConnectionLost() {
    if (_state == CallState.CALLING ||
        _state == CallState.RINGING ||
        _state == CallState.IN_CALL) {
      _endCall(reason: 'peer_disconnected');
    }
  }

  Future<void> _endCall({String? reason}) async {
    if (_state == CallState.ENDED || _state == CallState.IDLE) {
      _log('🔴 _endCall() — already in state=$_state, skipping');
      return;
    }

    _log('🔴 _endCall() — reason=$reason, state=$_state');

    // Отключаем LiveKit
    await _liveKitService.disconnect();

    // Отписываемся от LiveKit listeners
    if (_liveKitRemoteVideoListener != null) {
      _liveKitService.remoteVideoTrack.removeListener(_liveKitRemoteVideoListener!);
      _liveKitRemoteVideoListener = null;
    }
    if (_liveKitStateListener != null) {
      _liveKitService.connectionState.removeListener(_liveKitStateListener!);
      _liveKitStateListener = null;
    }

    _lastEndReason = reason;
    _lastCallEndTimestamp = DateTime.now().millisecondsSinceEpoch;

    await CallRingtoneService().stopAllCallSounds();
    _disposePeerResources();

    _localStreamController.add(null);
    _remoteStreamController.add(null);
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

    _lastCallEndTimestamp = DateTime.now().millisecondsSinceEpoch;

    _state = CallState.IDLE;
    _currentCallId = null;
    _remoteUserId = null;
    _remoteUserName = null;
    _isCameraOn = true;
    _isMicOn = true;
    _isFrontCamera = true;
    _disposePeerResources();
    _isIncomingDialogOpen = false;
    _isCallScreenOpen = false;
    _isMinimized = false;
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
    _localStreamController.close();
    _remoteStreamController.close();
    _incomingCallController.close();
    _minimizedController.close();
  }

  /// Пишет лог одновременно в print (adb) и в файл (CallLogger)
  void _log(String message) {
    print('[CALL_SERVICE] $message');
    _callLogger.log('CallService', message);
  }
}
