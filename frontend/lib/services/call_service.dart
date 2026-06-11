import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'socket_service.dart';

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

  Future<void> init() async {
    await _requestPermissions();
    _setupSocketListeners();
  }

  /// Отмечает, что экран звонка открыт (предотвращает дубли)
  void markCallScreenOpen() => _isCallScreenOpen = true;

  /// Отмечает, что экран звонка закрыт
  void markCallScreenClosed() => _isCallScreenOpen = false;

  /// Проверяет, открыт ли уже экран звонка
  bool get isCallScreenOpen => _isCallScreenOpen;

  Future<void> _requestPermissions() async {
    // Разрешения запрашиваются нативными плагинами на уровне платформы
    // и через getUserMedia в flutter_webrtc
  }

  void _setupSocketListeners() {
    // Защита от повторной регистрации: listeners навешиваются только один раз
    if (_listenersAttached) return;
    _listenersAttached = true;

    _socketService.onCallEvent('call:incoming', (data) {
      // Игнорируем входящий звонок, если уже на звонке
      if (_state == CallState.CALLING ||
          _state == CallState.RINGING ||
          _state == CallState.IN_CALL) {
        return;
      }
      _state = CallState.RINGING;
      _currentCallId = data['callId'];
      _remoteUserId = data['callerId'];
      _remoteUserName = data['callerName'] ?? 'Пользователь';
      _stateController.add(_state);
      // Оповещаем UI о входящем звонке для открытия экрана
      _incomingCallController.add({
        'callId': data['callId'],
        'callerId': data['callerId'],
        'callerName': data['callerName'] ?? 'Пользователь',
      });
    });

    _socketService.onCallEvent('call:accepted', (data) async {
      // Только caller получает call:accepted и создаёт offer
      _state = CallState.IN_CALL;
      _stateController.add(_state);
      await _startPeerConnection(isCaller: true);
    });

    _socketService.onCallEvent('call:signal', (data) async {
      if (data['type'] == 'candidate') {
        if (_peerConnection != null) {
          await _peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
        }
      } else if (data['type'] == 'offer') {
        // Callee получает offer — создаёт peer connection и answer
        _state = CallState.IN_CALL;
        _stateController.add(_state);
        await _startPeerConnection(isCaller: false);
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(data['sdp'], data['type']),
        );
        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        _socketService.sendCallSignal(_currentCallId!, {
          'type': 'answer',
          'sdp': answer.sdp,
        });
      } else if (data['type'] == 'answer') {
        // Caller получает answer — устанавливает remote description
        if (_peerConnection != null) {
          await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(data['sdp'], data['type']),
          );
        }
      }
    });

    _socketService.onCallEvent('call:ended', (data) {
      _endCall();
    });
  }

  Future<void> startCall(int userId) async {
    _state = CallState.CALLING;
    _remoteUserId = userId;
    _stateController.add(_state);

    _socketService.sendCallEvent('call:start', {
      'calleeId': userId,
    });
  }

  Future<void> acceptCall() async {
    // Callee только принимает звонок, НЕ создаёт peer connection
    // Peer connection будет создан после получения offer через call:signal
    _socketService.sendCallEvent('call:accept', {
      'callId': _currentCallId,
    });
  }

  Future<void> rejectCall() async {
    _socketService.sendCallEvent('call:reject', {
      'callId': _currentCallId,
    });
    _reset();
  }

  Future<void> endCall() async {
    _socketService.sendCallEvent('call:end', {
      'callId': _currentCallId,
    });
    _endCall();
  }

  Future<void> _startPeerConnection({required bool isCaller}) async {
    final mediaConstraints = {
      'audio': true,
      'video': {
        'facingMode': _isFrontCamera ? 'user' : 'environment',
      },
    };
    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _localStreamController.add(_localStream);

    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };
    _peerConnection = await createPeerConnection(config);

    _peerConnection!.addStream(_localStream!);

    _peerConnection!.onIceCandidate = (candidate) {
      _socketService.sendCallSignal(_currentCallId!, {
        'type': 'candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _peerConnection!.onAddStream = (stream) {
      _remoteStream = stream;
      _remoteStreamController.add(_remoteStream);
    };

    if (isCaller) {
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      _socketService.sendCallSignal(_currentCallId!, {
        'type': 'offer',
        'sdp': offer.sdp,
      });
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
    _peerConnection?.close();
    _peerConnection = null;
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream = null;
    _remoteStream = null;
    _state = CallState.ENDED;
    _stateController.add(_state);
    Future.delayed(const Duration(seconds: 1), () => _reset());
  }

  void _reset() {
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
  }

  void dispose() {
    _stateController.close();
    _localStreamController.close();
    _remoteStreamController.close();
    _incomingCallController.close();
  }
}
