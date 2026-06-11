import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'socket_service.dart';
import 'call_logger.dart';

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

  // Защита от повторной регистрации listeners
  bool _listenersAttached = false;

  // Флаг: открыт ли экран звонка (для предотвращения дублей)
  bool _isCallScreenOpen = false;

  // StreamController для UI
  final _stateController = StreamController<CallState>.broadcast();
  final _localStreamController = StreamController<MediaStream?>.broadcast();
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();

  // Стрим для оповещения о входящем звонке (глобальная навигация)
  final _incomingCallController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get incomingCallStream => _incomingCallController.stream;

  Stream<CallState> get stateStream => _stateController.stream;
  Stream<MediaStream?> get localStream => _localStreamController.stream;
  Stream<MediaStream?> get remoteStream => _remoteStreamController.stream;

  CallState get state => _state;
  bool get isCameraOn => _isCameraOn;
  bool get isMicOn => _isMicOn;
  int? get remoteUserId => _remoteUserId;
  String? get remoteUserName => _remoteUserName;
  int? get currentCallId => _currentCallId;

  Future<void> init() async {
    _log('🔧 init() called');
    await _requestPermissions();
    _setupSocketListeners();

    // Если socket ещё не подключён — listeners не зарегистрируются.
    // Подписываемся на событие подключения socket, чтобы донавесить listeners.
    _log('🔧 init() — checking if socket is already connected...');
    final socket = _socketService.socket;
    if (socket != null && socket.connected) {
      _log('🔧 init() — socket is already connected (id: ${socket.id}), listeners should be registered');
    } else {
      _log('🔧 init() — ⚠️ socket is NOT connected yet (socket=${socket?.id}, connected=${socket?.connected})');
      _log('🔧 init() — ⚠️ listeners may NOT be registered! Will retry on socket connect...');
      // Подписываемся на connect через socket.io on(), чтобы донавесить listeners
      socket?.on('connect', (_) {
        _log('🔧 init() — socket connected AFTER init, retrying _setupSocketListeners()');
        _listenersAttached = false; // Сбрасываем флаг для повторной регистрации
        _setupSocketListeners();
      });
    }
  }

  /// Отмечает, что экран звонка открыт (предотвращает дубли)
  void markCallScreenOpen() => _isCallScreenOpen = true;

  /// Отмечает, что экран звонка закрыт
  void markCallScreenClosed() => _isCallScreenOpen = false;

  /// Проверяет, открыт ли уже экран звонка
  bool get isCallScreenOpen => _isCallScreenOpen;

  Future<void> _requestPermissions() async {
    _log('_requestPermissions() called — permissions are requested via getUserMedia natively');
  }

  void _setupSocketListeners() {
    // Защита от повторной регистрации: listeners навешиваются только один раз
    if (_listenersAttached) {
      _log('🔌 _setupSocketListeners() — already attached, skipping');
      return;
    }
    _log('🔌 _setupSocketListeners() — registering listeners...');

    // Проверяем, что socket не null
    final socket = _socketService.socket;
    if (socket == null) {
      _log('🔌 _setupSocketListeners() — ⚠️⚠️⚠️ _socketService.socket is NULL! Listeners will NOT be registered!');
      _log('🔌 _setupSocketListeners() — 💡 This means CallService.init() was called before SocketService.connect()');
      _log('🔌 _setupSocketListeners() — 💡 Setting _listenersAttached=false so retry can happen');
      _listenersAttached = false;
      return;
    }
    if (!socket.connected) {
      _log('🔌 _setupSocketListeners() — ⚠️ socket exists but NOT CONNECTED yet (id: ${socket.id})');
      _log('🔌 _setupSocketListeners() — 💡 Listeners will be registered anyway (socket.io queues them)');
    }

    _listenersAttached = true;
    _log('🔌 _setupSocketListeners() — ✅ registering: call:incoming, call:accepted, call:signal, call:ended');
    _log('🔌 _setupSocketListeners() — socket.id=${socket.id}, socket.connected=${socket.connected}');

    _socketService.onCallEvent('call:incoming', (data) {
      _log('📞📞📞 call:incoming RECEIVED — data: $data');
      _log('📞 call:incoming — current state=$_state, _currentCallId=$_currentCallId');
      // Игнорируем входящий звонок, если уже на звонке
      if (_state == CallState.CALLING ||
          _state == CallState.RINGING ||
          _state == CallState.IN_CALL) {
        _log('⚠️ call:incoming ignored — already in call, state=$_state');
        return;
      }
      _state = CallState.RINGING;
      _currentCallId = data['callId'];
      _remoteUserId = data['callerId'];
      _remoteUserName = data['callerName'] ?? 'Пользователь';
      _stateController.add(_state);
      _log('✅ call:incoming processed — callId=$_currentCallId, callerId=$_remoteUserId, callerName=$_remoteUserName');
      // Оповещаем UI о входящем звонке для открытия экрана
      _log('📞 call:incoming — emitting to _incomingCallController');
      _incomingCallController.add({
        'callId': data['callId'],
        'callerId': data['callerId'],
        'callerName': data['callerName'] ?? 'Пользователь',
      });
      _log('📞 call:incoming — emitted to _incomingCallController');
    });

    _socketService.onCallEvent('call:accepted', (data) async {
      _log('📞📞📞 call:accepted RECEIVED — data: $data');
      _log('📞 call:accepted — current state=$_state, _currentCallId=$_currentCallId');
      // Сохраняем callId из ответа, если ещё не установлен
      if (_currentCallId == null && data['callId'] != null) {
        _currentCallId = data['callId'];
        _log('📝 callId set from call:accepted: $_currentCallId');
      } else {
        _log('📝 callId already set: $_currentCallId (from data: ${data['callId']})');
      }
      // Только caller получает call:accepted и создаёт offer
      _log('📞 call:accepted — transitioning state: $_state -> IN_CALL');
      _state = CallState.IN_CALL;
      _stateController.add(_state);
      _log('🚀🚀🚀 Starting peer connection as CALLER (isCaller: true)');
      _log('🚀 _currentCallId=$_currentCallId, _remoteUserId=$_remoteUserId');
      await _startPeerConnection(isCaller: true);
      _log('📞 call:accepted — _startPeerConnection completed');
    });

    _socketService.onCallEvent('call:signal', (data) async {
      _log('📡📡📡 call:signal RECEIVED — type=${data['type']}, full data: $data');
      _log('📡 call:signal — current state=$_state, _currentCallId=$_currentCallId, _peerConnection=${_peerConnection != null ? 'exists' : 'NULL'}');
      if (data['type'] == 'candidate') {
        if (_peerConnection != null) {
          _log('🧊 Adding ICE candidate: ${data['candidate']}');
          _log('🧊 sdpMid=${data['sdpMid']}, sdpMLineIndex=${data['sdpMLineIndex']}');
          try {
            await _peerConnection!.addCandidate(
              RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              ),
            );
            _log('✅ ICE candidate added successfully');
          } catch (e) {
            _log('❌❌❌ ICE candidate add FAILED: $e');
          }
        } else {
          _log('⚠️⚠️⚠️ ICE candidate received but _peerConnection is NULL');
        }
      } else if (data['type'] == 'offer') {
        _log('📄📄📄 Offer received — starting peer connection as CALLEE (isCaller: false)');
        _log('📄 Offer sdp length: ${data['sdp']?.length}');
        // Callee получает offer — создаёт peer connection и answer
        _log('📄 call:signal(offer) — transitioning state: $_state -> IN_CALL');
        _state = CallState.IN_CALL;
        _stateController.add(_state);
        await _startPeerConnection(isCaller: false);
        _log('📄 Setting remote description (offer)');
        try {
          await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(data['sdp'], data['type']),
          );
          _log('✅ Remote description set from offer');
        } catch (e) {
          _log('❌❌❌ setRemoteDescription(offer) FAILED: $e');
          return;
        }
        _log('📄 Creating answer...');
        try {
          final answer = await _peerConnection!.createAnswer();
          _log('✅ Answer created — type: ${answer.type}, sdp length: ${answer.sdp?.length}');
          _log('📄 Setting local description (answer)');
          await _peerConnection!.setLocalDescription(answer);
          _log('✅ Local description set');
          _log('📤 Sending answer via signalling');
          _socketService.sendCallSignal(_currentCallId!, {
            'type': 'answer',
            'sdp': answer.sdp,
          });
          _log('✅ Answer sent');
        } catch (e) {
          _log('❌❌❌ Answer creation/sending FAILED: $e');
        }
      } else if (data['type'] == 'answer') {
        _log('📄📄📄 Answer received — setting remote description');
        _log('📄 Answer sdp length: ${data['sdp']?.length}');
        // Caller получает answer — устанавливает remote description
        if (_peerConnection != null) {
          try {
            await _peerConnection!.setRemoteDescription(
              RTCSessionDescription(data['sdp'], data['type']),
            );
            _log('✅ Remote description set from answer');
          } catch (e) {
            _log('❌❌❌ setRemoteDescription(answer) FAILED: $e');
          }
        } else {
          _log('⚠️⚠️⚠️ Answer received but _peerConnection is NULL');
        }
      } else {
        _log('⚠️ call:signal — unknown type: ${data['type']}');
      }
    });

    _socketService.onCallEvent('call:ended', (data) {
      _log('📞📞📞 call:ended RECEIVED — data: $data');
      _log('📞 call:ended — current state=$_state, _currentCallId=$_currentCallId');
      _endCall();
    });

    _log('🔌 _setupSocketListeners() — ✅ ALL listeners registered');
  }

  Future<void> startCall(int userId) async {
    _log('📞📞📞 startCall() called — userId=$userId');
    _log('📞 startCall() — current state=$_state, _currentCallId=$_currentCallId');
    // Инициализируем логгер для нового звонка
    await _callLogger.init();
    _log('📝 Call log file initialized');
    _log('📞 startCall() — transitioning state: $_state -> CALLING');
    _state = CallState.CALLING;
    _remoteUserId = userId;
    _stateController.add(_state);

    _log('📤 Sending call:start — calleeId=$userId');
    _log('📞 startCall() — checking socket before emit...');
    final socket = _socketService.socket;
    _log('📞 startCall() — socket=${socket?.id}, connected=${socket?.connected}');
    _socketService.sendCallEvent('call:start', {
      'calleeId': userId,
    });
    _log('📞 startCall() — call:start sent, waiting for call:accepted...');
    // callId будет получен в call:accepted от backend
  }

  Future<void> acceptCall() async {
    _log('✅✅✅ acceptCall() called — callId=$_currentCallId');
    _log('✅ acceptCall() — current state=$_state, _remoteUserId=$_remoteUserId');
    if (_currentCallId == null) {
      _log('⚠️⚠️⚠️ acceptCall() — _currentCallId is NULL! Cannot accept call without callId');
      return;
    }
    // Callee только принимает звонок, НЕ создаёт peer connection
    // Peer connection будет создан после получения offer через call:signal
    _log('✅ acceptCall() — sending call:accept with callId=$_currentCallId');
    _socketService.sendCallEvent('call:accept', {
      'callId': _currentCallId,
    });
    _log('✅ acceptCall() — call:accept sent');
  }

  Future<void> rejectCall() async {
    _log('❌❌❌ rejectCall() called — callId=$_currentCallId');
    _log('❌ rejectCall() — current state=$_state');
    if (_currentCallId == null) {
      _log('⚠️ rejectCall() — _currentCallId is NULL, sending null anyway');
    }
    _socketService.sendCallEvent('call:reject', {
      'callId': _currentCallId,
    });
    _log('❌ rejectCall() — call:reject sent, resetting state');
    _reset();
  }

  Future<void> endCall() async {
    _log('🔴🔴🔴 endCall() called — callId=$_currentCallId');
    _log('🔴 endCall() — current state=$_state, _remoteUserId=$_remoteUserId');
    _log('🔴 endCall() — sending call:end with callId=$_currentCallId');
    _socketService.sendCallEvent('call:end', {
      'callId': _currentCallId,
    });
    _log('🔴 endCall() — call:end sent, cleaning up');
    _endCall();
  }

  Future<void> _startPeerConnection({required bool isCaller}) async {
    _log('🔧🔧🔧 _startPeerConnection() — isCaller=$isCaller');
    _log('🔧 _startPeerConnection() — _currentCallId=$_currentCallId, _remoteUserId=$_remoteUserId');
    _log('🔧 _startPeerConnection() — _state=$_state, _peerConnection=${_peerConnection != null ? 'exists' : 'null'}');

    // ===== 1. Получаем локальный stream =====
    final mediaConstraints = {
      'audio': true,
      'video': {
        'facingMode': _isFrontCamera ? 'user' : 'environment',
      },
    };
    _log('🎥 Requesting getUserMedia with constraints: $mediaConstraints');
    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _log('✅ getUserMedia SUCCESS');
    } catch (e) {
      _log('❌❌❌ getUserMedia FAILED: $e');
      return;
    }

    // Диагностика локального stream
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      final audioTracks = _localStream!.getAudioTracks();
      _log('📊 Local stream tracks:');
      _log('    - Video tracks: ${videoTracks.length}');
      for (var t in videoTracks) {
        _log('      track: ${t.id}, enabled: ${t.enabled}, kind: ${t.kind}, label: ${t.label}');
      }
      _log('    - Audio tracks: ${audioTracks.length}');
      for (var t in audioTracks) {
        _log('      track: ${t.id}, enabled: ${t.enabled}, kind: ${t.kind}');
      }
      _log('    - Stream id: ${_localStream!.id}');
    } else {
      _log('❌❌❌ _localStream is NULL after getUserMedia');
    }
    _localStreamController.add(_localStream);

    // ===== 2. Создаём Peer Connection =====
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };
    _log('🔗 Creating RTCPeerConnection with config: $config');
    try {
      _peerConnection = await createPeerConnection(config);
      _log('✅ RTCPeerConnection created');
    } catch (e) {
      _log('❌❌❌ createPeerConnection FAILED: $e');
      return;
    }

    // ===== 3. Добавляем локальные track'и в peer connection через addTrack (v1.x API) =====
    if (_localStream != null) {
      _log('📤 Adding local tracks to peer connection via addTrack()');
      for (var track in _localStream!.getTracks()) {
        try {
          await _peerConnection!.addTrack(track, _localStream!);
          _log('✅ addTrack() — track: ${track.kind}, id: ${track.id}');
        } catch (e) {
          _log('❌❌❌ addTrack() FAILED for track ${track.kind}: $e');
        }
      }
    }

    // ===== 4. Обработка ICE candidates =====
    _peerConnection!.onIceCandidate = (candidate) {
      _log('🧊 onIceCandidate fired — candidate: ${candidate.candidate}');
      _log('    - sdpMid: ${candidate.sdpMid}, sdpMLineIndex: ${candidate.sdpMLineIndex}');
      _socketService.sendCallSignal(_currentCallId!, {
        'type': 'candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
      _log('📤 ICE candidate sent via signalling');
    };

    // ===== 5. Обработка remote track через onTrack (v1.x API) =====
    _peerConnection!.onTrack = (event) {
      _log('📥 onTrack FIRED — event.streams.length=${event.streams.length}');
      for (var s in event.streams) {
        _log('    - stream id: ${s.id}, videoTracks: ${s.getVideoTracks().length}, audioTracks: ${s.getAudioTracks().length}');
      }
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        _remoteStreamController.add(_remoteStream);
        _log('✅ Remote stream from onTrack assigned and emitted');
      } else {
        _log('⚠️ onTrack fired but event.streams is EMPTY');
      }
    };

    // ===== 6. Мониторинг состояния peer connection =====
    _peerConnection!.onIceConnectionState = (state) {
      _log('🔵 iceConnectionState changed: $state');
    };
    _peerConnection!.onConnectionState = (state) {
      _log('🔵 connectionState changed: $state');
    };
    _peerConnection!.onSignalingState = (state) {
      _log('🔵 signalingState changed: $state');
    };

    // ===== 7. Если caller — создаём offer =====
    if (isCaller) {
      _log('📄 Creating offer...');
      try {
        final offer = await _peerConnection!.createOffer();
        _log('✅ Offer created — type: ${offer.type}, sdp length: ${offer.sdp?.length}');
        _log('📄 Setting local description (offer)...');
        await _peerConnection!.setLocalDescription(offer);
        _log('✅ Local description set');
        _log('📤 Sending offer via signalling');
        _socketService.sendCallSignal(_currentCallId!, {
          'type': 'offer',
          'sdp': offer.sdp,
        });
        _log('✅ Offer sent');
      } catch (e) {
        _log('❌❌❌ Offer creation/sending FAILED: $e');
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

  void _endCall() {
    _log('🔴🔴🔴 _endCall() — cleaning up');
    _log('🔴 _endCall() — state=$_state, _currentCallId=$_currentCallId, _remoteUserId=$_remoteUserId');
    _log('🔴 _endCall() — _peerConnection=${_peerConnection != null ? 'closing' : 'already null'}');
    _log('🔴 _endCall() — _localStream=${_localStream != null ? 'exists' : 'null'}, _remoteStream=${_remoteStream != null ? 'exists' : 'null'}');
    _peerConnection?.close();
    _peerConnection = null;
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream = null;
    _remoteStream = null;
    _state = CallState.ENDED;
    _stateController.add(_state);
    _log('✅ Cleanup done, state=ENDED');
    // Закрываем лог-файл
    _callLogger.close();
    Future.delayed(const Duration(seconds: 1), () => _reset());
  }

  void _reset() {
    _log('🔄 _reset() — resetting all state');
    _state = CallState.IDLE;
    _currentCallId = null;
    _remoteUserId = null;
    _remoteUserName = null;
    _isCameraOn = true;
    _isMicOn = true;
    _isFrontCamera = true;
    // _isCallScreenOpen НЕ сбрасывается здесь —
    // флагом управляет только CallScreen через markCallScreenClosed()
    _stateController.add(_state);
    _localStreamController.add(null);
    _remoteStreamController.add(null);
    _log('🔄 _reset() — state reset to IDLE');
  }

  void dispose() {
    _stateController.close();
    _localStreamController.close();
    _remoteStreamController.close();
    _incomingCallController.close();
  }

  /// Пишет лог одновременно в print (adb) и в файл (CallLogger)
  void _log(String message) {
    print('[CALL_SERVICE] $message');
    _callLogger.log('CallService', message);
  }
}
