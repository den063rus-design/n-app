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
  bool _isCameraOn = true;
  bool _isMicOn = true;
  bool _isFrontCamera = true;

  // StreamController для UI
  final _stateController = StreamController<CallState>.broadcast();
  final _localStreamController = StreamController<MediaStream?>.broadcast();
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();

  Stream<CallState> get stateStream => _stateController.stream;
  Stream<MediaStream?> get localStream => _localStreamController.stream;
  Stream<MediaStream?> get remoteStream => _remoteStreamController.stream;

  CallState get state => _state;
  bool get isCameraOn => _isCameraOn;
  bool get isMicOn => _isMicOn;
  int? get remoteUserId => _remoteUserId;

  Future<void> init() async {
    await _requestPermissions();
    _setupSocketListeners();
  }

  Future<void> _requestPermissions() async {
    // Разрешения запрашиваются через permission_handler на уровне платформы
    // и через getUserMedia в flutter_webrtc
  }

  void _setupSocketListeners() {
    _socketService.onCallEvent('call:incoming', (data) {
      _state = CallState.RINGING;
      _currentCallId = data['callId'];
      _remoteUserId = data['callerId'];
      _stateController.add(_state);
    });

    _socketService.onCallEvent('call:accepted', (data) async {
      _state = CallState.IN_CALL;
      _stateController.add(_state);
      await _startPeerConnection();
    });

    _socketService.onCallEvent('call:signal', (data) async {
      if (_peerConnection != null) {
        if (data['type'] == 'candidate') {
          await _peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
        } else if (data['type'] == 'offer' || data['type'] == 'answer') {
          await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(data['sdp'], data['type']),
          );
          if (data['type'] == 'offer') {
            final answer = await _peerConnection!.createAnswer();
            await _peerConnection!.setLocalDescription(answer);
            _socketService.sendCallSignal(_currentCallId!, {
              'type': 'answer',
              'sdp': answer.sdp,
            });
          }
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
    _socketService.sendCallEvent('call:accept', {
      'callId': _currentCallId,
    });
    await _startPeerConnection();
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

  Future<void> _startPeerConnection() async {
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

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    _socketService.sendCallSignal(_currentCallId!, {
      'type': 'offer',
      'sdp': offer.sdp,
    });
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
    _isCameraOn = true;
    _isMicOn = true;
    _isFrontCamera = true;
    _stateController.add(_state);
    _localStreamController.add(null);
    _remoteStreamController.add(null);
  }

  void dispose() {
    _stateController.close();
    _localStreamController.close();
    _remoteStreamController.close();
  }
}