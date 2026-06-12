import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../app/app.dart';
import 'socket_service.dart';
import 'call_logger.dart';
import 'call_ringtone_service.dart';

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

  // WebRTC
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

  // Флаг: были ли уже навешены listeners (чтобы не дублировать)
  bool _listenersAttached = false;

  // Флаг: открыт ли экран звонка (для предотвращения дублей)
  bool _isCallScreenOpen = false;

  // Флаг: открыт ли диалог входящего звонка (для предотвращения дублей)
  bool _isIncomingDialogOpen = false;

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

  Future<void> init() async {
    _log('🔧 init()');
    await _requestPermissions();
    _socketService.setOnConnectCallback(_setupSocketListeners);
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
  /// Вызывается, когда пользователь тапнул по call push, но CallService
  /// ещё не в состоянии RINGING (например, приложение было убито).
  ///
  /// Параметры принимаются как String (так как из FCM data все значения —
  /// строки) и парсятся в int внутри метода.
  void hydrateIncomingCallFromPush({
    required String callId,
    required String callerId,
    required String callerName,
  }) {
    _log('📞 hydrateIncomingCallFromPush() — callId=$callId, callerId=$callerId, callerName=$callerName');

    // Парсим String в int
    final parsedCallId = int.tryParse(callId);
    final parsedCallerId = int.tryParse(callerId);

    if (parsedCallId == null || parsedCallerId == null) {
      _log('⚠️ hydrateIncomingCallFromPush — failed to parse callId or callerId, ignoring');
      return;
    }

    // Если уже на звонке — игнорируем (включая CALLING)
    if (_state == CallState.CALLING ||
        _state == CallState.RINGING ||
        _state == CallState.IN_CALL) {
      _log('⚠️ hydrateIncomingCallFromPush — already in call, state=$_state, ignoring');
      return;
    }

    // Отменяем отложенный сброс
    _resetTimer?.cancel();

    // Полный сброс состояния перед установкой нового звонка
    _hardReset();

    // Устанавливаем RINGING
    _state = CallState.RINGING;
    _currentCallId = parsedCallId;
    _remoteUserId = parsedCallerId;
    _remoteUserName = callerName;
    _stateController.add(_state);
    _log('✅ hydrateIncomingCallFromPush — state set to RINGING');
  }

  Future<void> _requestPermissions() async {
    // Разрешения запрашиваются централизованно в AppPermissionsService при старте.
    // getUserMedia запросит их нативно, если потребуется.
  }

  void _setupSocketListeners() {
    _log('🔌 _setupSocketListeners()');

    // Проверяем, что socket не null
    final socket = _socketService.socket;
    if (socket == null) {
      _log('🔌 _setupSocketListeners() — socket is NULL');
      return;
    }

    _listenersAttached = true;
    _log('🔌 registering: call:incoming, call:accepted, call:signal, call:ended, call:rejected');

    _socketService.onCallEvent('call:incoming', (data) {
      _log('📞 call:incoming — data: $data, state=$_state');
      // Игнорируем входящий звонок, если уже на звонке
      if (_state == CallState.CALLING ||
          _state == CallState.RINGING ||
          _state == CallState.IN_CALL) {
        _log('⚠️ call:incoming ignored — already in call, state=$_state');
        return;
      }
      // Игнорируем входящий звонок, если экран звонка уже открыт
      // (защита от дублей — экран мог быть открыт через push-уведомление)
      if (_isCallScreenOpen) {
        _log('⚠️ call:incoming ignored — call screen already open, state=$_state');
        return;
      }
      // Игнорируем входящий звонок, если диалог входящего звонка уже открыт
      // (защита от дублей — предотвращает создание второго диалога)
      if (_isIncomingDialogOpen) {
        _log('⚠️ call:incoming ignored — incoming dialog already open, state=$_state');
        return;
      }
      // Отменяем отложенный сброс (если был завершён предыдущий звонок)
      _resetTimer?.cancel();
      // Полный сброс состояния перед установкой нового звонка
      _hardReset();
      // Устанавливаем RINGING
      _state = CallState.RINGING;
      _currentCallId = data['callId'];
      _remoteUserId = data['callerId'];
      _remoteUserName = data['callerName'] ?? 'Пользователь';
      _stateController.add(_state);
      _log('✅ call:incoming processed — callId=$_currentCallId, callerId=$_remoteUserId');
      // Оповещаем UI о входящем звонке для открытия экрана
      _incomingCallController.add({
        'callId': data['callId'],
        'callerId': data['callerId'],
        'callerName': data['callerName'] ?? 'Пользователь',
      });
    });

    _socketService.onCallEvent('call:accepted', (data) async {
      _log('📞 call:accepted — data: $data, state=$_state');

      // Останавливаем все звуки звонка (исходящий гудок у звонящего)
      await CallRingtoneService().stopAllCallSounds();

      // Сохраняем callId из ответа, если ещё не установлен
      if (_currentCallId == null && data['callId'] != null) {
        _currentCallId = data['callId'];
      }
      // Только caller получает call:accepted и создаёт offer
      _state = CallState.IN_CALL;
      _stateController.add(_state);
      _log('🚀 Starting peer connection as CALLER');
      await _startPeerConnection(isCaller: true);
    });

    _socketService.onCallEvent('call:signal', (data) async {
      _log('📡 call:signal — type=${data['type']}, state=$_state');

      // Игнорируем сигналы от старых/чужих звонков
      if (data['callId'] != null && data['callId'] != _currentCallId) {
        _log('📡 call:signal — ignoring signal for different call: ${data['callId']}');
        return;
      }

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
        _log('📄 Offer received — starting peer connection as CALLEE');
        _state = CallState.IN_CALL;
        _stateController.add(_state);
        await _startPeerConnection(isCaller: false);
        try {
          await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(data['sdp'], data['type']),
          );
        } catch (e) {
          _log('❌ setRemoteDescription(offer) FAILED: $e');
          return;
        }
        try {
          final answer = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(answer);
          _socketService.sendCallSignal(_currentCallId!, {
            'type': 'answer',
            'sdp': answer.sdp,
          });
          _log('✅ Answer sent');
        } catch (e) {
          _log('❌ Answer creation/sending FAILED: $e');
        }
      } else if (data['type'] == 'answer') {
        _log('📄 Answer received — setting remote description');
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

      // Идемпотентность: игнорируем, если уже завершён или в IDLE
      if (_state == CallState.IDLE || _state == CallState.ENDED) {
        _log('📞 call:ended — already in state=$_state, skipping');
        return;
      }

      // Останавливаем все звуки звонка
      CallRingtoneService().stopAllCallSounds();

      final reason = data['reason'] as String?;
      _endCall(reason: reason);
      if (reason == 'rejected') {
        _showSnackbar('Звонок отклонён');
      } else if (reason == 'expired') {
        _showSnackbar('Звонок уже завершён');
      }
      // no_answer — не показываем снэкбар
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

  Future<void> startCall(int userId) async {
    _log('📞 startCall() — userId=$userId, state=$_state');

    // Отменяем отложенный сброс (если был завершён предыдущий звонок)
    _resetTimer?.cancel();

    // Сбрасываем причину завершения предыдущего звонка
    _lastEndReason = null;
    // Сбрасываем stale guard timestamp — начинается новый звонок
    _lastCallEndTimestamp = null;

    // ===== ВАЖНО: разрешаем startCall только из IDLE =====
    if (_state != CallState.IDLE) {
      _log('⚠️ startCall() — state=$_state, forcing hard reset');
      _hardReset();
    }

    // Сбрасываем minimized-статус при старте нового звонка
    _isMinimized = false;
    _minimizedController.add(false);

    // Инициализируем логгер для нового звонка
    await _callLogger.init();

    _state = CallState.CALLING;
    _remoteUserId = userId;
    _stateController.add(_state);

    _socketService.sendCallEvent('call:start', {
      'calleeId': userId,
    });
    _log('📞 call:start sent, waiting for call:accepted...');

    // Запускаем исходящий гудок у звонящего
    await CallRingtoneService().playOutgoingRingbackTone();
  }

  Future<void> acceptCall() async {
    _log('✅ acceptCall() — callId=$_currentCallId, state=$_state');

    // Останавливаем все звуки звонка (входящий рингтон + исходящий гудок)
    await CallRingtoneService().stopAllCallSounds();

    // Отменяем отложенный сброс (если был завершён предыдущий звонок)
    _resetTimer?.cancel();

    if (_currentCallId == null) {
      _log('⚠️ acceptCall() — _currentCallId is NULL');
      return;
    }

    // Сохраняем callId для проверки в таймауте
    final callId = _currentCallId;

    _socketService.sendCallEvent('call:accept', {
      'callId': callId,
    });
    _log('✅ call:accept sent');

    // Ожидаем подтверждения: если через 5 секунд звонок всё ещё в состоянии RINGING
    // (не перешёл в IN_CALL через call:signal), значит звонок протух
    await Future.delayed(const Duration(seconds: 5));

    // Проверяем, не перешёл ли уже звонок в активное состояние
    if (_state == CallState.RINGING && _currentCallId == callId) {
      _log('⚠️ acceptCall() — timeout: call not accepted, callId=$callId');
      _endCall(reason: 'expired');
      _showSnackbar('Звонок уже завершён');
    }
  }

  Future<void> rejectCall() async {
    _log('❌ rejectCall() — callId=$_currentCallId, state=$_state');

    // Останавливаем все звуки звонка
    await CallRingtoneService().stopAllCallSounds();

    if (_currentCallId == null) {
      _log('⚠️ rejectCall() — _currentCallId is NULL');
    }
    _socketService.sendCallEvent('call:reject', {
      'callId': _currentCallId,
    });
    _log('❌ call:reject sent');
    // Используем _endCall с reason='rejected', чтобы UI получил ENDED
    // и показал сообщение "Звонок отклонён" перед закрытием
    _endCall(reason: 'rejected');
  }

  Future<void> endCall() async {
    _log('🔴 endCall() — callId=$_currentCallId, state=$_state');

    if (_currentCallId != null) {
      _socketService.sendCallEvent('call:end', {
        'callId': _currentCallId,
      });
    } else {
      _log('🔴 endCall() — no active call, skipping socket event');
    }

    _endCall();
  }

  Future<void> _startPeerConnection({required bool isCaller}) async {
    _log('🔧 _startPeerConnection() — isCaller=$isCaller');

    // ===== 1. Получаем локальный stream =====
    final mediaConstraints = {
      'audio': true,
      'video': {
        'facingMode': _isFrontCamera ? 'user' : 'environment',
      },
    };
    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    } catch (e) {
      _log('❌ getUserMedia FAILED: $e');
      return;
    }
    _localStreamController.add(_localStream);

    // ===== 2. Создаём Peer Connection =====
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };
    try {
      _peerConnection = await createPeerConnection(config);
    } catch (e) {
      _log('❌ createPeerConnection FAILED: $e');
      return;
    }

    // ===== 3. Добавляем локальные track'и =====
    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }

    // ===== 4. Обработка ICE candidates =====
    _peerConnection!.onIceCandidate = (candidate) {
      _socketService.sendCallSignal(_currentCallId!, {
        'type': 'candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    // ===== 5. Обработка remote track =====
    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        _remoteStreamController.add(_remoteStream);
        _log('✅ Remote stream received');
      }
    };

    // ===== 6. Если caller — создаём offer =====
    if (isCaller) {
      try {
        final offer = await _peerConnection!.createOffer();
        await _peerConnection!.setLocalDescription(offer);
        _socketService.sendCallSignal(_currentCallId!, {
          'type': 'offer',
          'sdp': offer.sdp,
        });
        _log('✅ Offer sent');
      } catch (e) {
        _log('❌ Offer creation/sending FAILED: $e');
      }
    }
  }

  void toggleCamera() {
    _isFrontCamera = !_isFrontCamera;
    if (_localStream != null) {
      _localStream!.getVideoTracks().forEach((track) {
        track.switchCamera();
      });
    }
  }

  void toggleMic() {
    _isMicOn = !_isMicOn;
    if (_localStream != null) {
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = _isMicOn;
      });
    }
  }

  void toggleCameraVideo() {
    _isCameraOn = !_isCameraOn;
    if (_localStream != null) {
      _localStream!.getVideoTracks().forEach((track) {
        track.enabled = _isCameraOn;
      });
    }
  }

  void _showSnackbar(String message) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _endCall({String? reason}) async {
    // Идемпотентность: если уже завершён или в IDLE — выходим
    if (_state == CallState.ENDED || _state == CallState.IDLE) {
      _log('🔴 _endCall() — already in state=$_state, skipping');
      return;
    }

    _log('🔴 _endCall() — reason=$reason, state=$_state');

    // Сохраняем причину завершения
    _lastEndReason = reason;
    // Сохраняем timestamp завершения для stale push guard
    _lastCallEndTimestamp = DateTime.now().millisecondsSinceEpoch;

    // Останавливаем все звуки звонка (await — чтобы звуки гарантированно остановились)
    await CallRingtoneService().stopAllCallSounds();

    // Немедленно уведомляем UI, что стримов больше нет
    _localStreamController.add(null);
    _remoteStreamController.add(null);
    _state = CallState.ENDED;
    _stateController.add(_state);
    // Сбрасываем флаг минимизации
    _isMinimized = false;
    _log('✅ _endCall() — state=ENDED');
    // Закрываем лог-файл
    _callLogger.close();
    // Полный сброс состояния через 2 секунды (с возможностью отмены)
    // Увеличен с 300ms до 2000ms, чтобы новый входящий звонок успел отменить таймер
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 2000), () {
      _hardReset();
    });
  }

  /// Полный сброс ВСЕГО состояния звонка.
  /// Вызывается после завершения звонка, при reject, при старте нового звонка из не-IDLE.
  void _hardReset() {
    _log('🔄 _hardReset()');

    // Останавливаем все звуки звонка
    CallRingtoneService().stopAllCallSounds();

    // Сохраняем timestamp сброса для stale push guard в PushService
    _lastCallEndTimestamp = DateTime.now().millisecondsSinceEpoch;

    _state = CallState.IDLE;
    _currentCallId = null;
    _remoteUserId = null;
    _remoteUserName = null;
    _isCameraOn = true;
    _isMicOn = true;
    _isFrontCamera = true;
    _peerConnection?.close();
    _peerConnection = null;
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream = null;
    _remoteStream = null;
    _isIncomingDialogOpen = false;
    _isCallScreenOpen = false;
    _isMinimized = false;
    _lastEndReason = null;
    // Явно уведомляем подписчиков stateStream о возврате в IDLE.
    // _endCall() отправляет ENDED, но через 2 секунды _hardReset() переводит состояние в IDLE.
    // Без этого эмита StreamBuilder в call_screen.dart останется на ENDED, что может вызвать
    // лишний rebuild с ENDED-UI или конфуз при проверке snapshot.data == CallState.ENDED.
    _stateController.add(CallState.IDLE);
    // _localStreamController.add(null) и _remoteStreamController.add(null) НЕ вызываются —
    // _endCall() уже отправил null в stream-контроллеры.
  }

  /// Публичный метод полного сброса состояния звонка.
  /// Безопасен для вызова при detached socket — не шлёт socket events.
  void hardReset() {
    _hardReset();
  }

  void dispose() {
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
