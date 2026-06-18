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

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];

  CallState _state = CallState.IDLE;
  int? _currentCallId;
  int? _remoteUserId;
  String? _remoteUserName;
  bool _isCameraOn = true;
  bool _isMicOn = true;
  bool _isFrontCamera = true;
  bool _isCallScreenOpen = false;
  bool _isIncomingDialogOpen = false;
  bool _isMinimized = false;
  bool _isAcceptingCall = false;
  bool _isEndingCall = false;
  Timer? _resetTimer;
  StreamSubscription<bool>? _connectionSubscription;

  final _stateController = StreamController<CallState>.broadcast();
  final _localStreamController = StreamController<MediaStream?>.broadcast();
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  final _incomingCallController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _minimizedController = StreamController<bool>.broadcast();

  String? _lastEndReason;
  int? _lastCallEndTimestamp;

  Stream<Map<String, dynamic>> get incomingCallStream =>
      _incomingCallController.stream;
  Stream<bool> get minimizedStream => _minimizedController.stream;
  Stream<CallState> get stateStream => _stateController.stream;
  Stream<MediaStream?> get localStream => _localStreamController.stream;
  Stream<MediaStream?> get remoteStream => _remoteStreamController.stream;

  MediaStream? get currentLocalStream => _localStream;
  MediaStream? get currentRemoteStream => _remoteStream;

  CallState get state => _state;
  bool get isCameraOn => _isCameraOn;
  bool get isMicOn => _isMicOn;
  int? get remoteUserId => _remoteUserId;
  String? get remoteUserName => _remoteUserName;
  int? get currentCallId => _currentCallId;
  bool get isMinimized => _isMinimized;
  bool get isIncomingDialogOpen => _isIncomingDialogOpen;
  bool get isCallScreenOpen => _isCallScreenOpen;
  String? get lastEndReason => _lastEndReason;
  int? get lastCallEndTimestamp => _lastCallEndTimestamp;

  Future<void> init() async {
    _log('🔧 init()');
    await _requestPermissions();
    _socketService.setOnConnectCallback(_setupSocketListeners);
    _connectionSubscription ??=
        _socketService.onConnectionChanged.listen((connected) {
      if (connected) {
        _log('🔌 socket reconnected — re-registering call listeners');
        _setupSocketListeners();
      }
    });
    if (_socketService.isConnected) {
      _setupSocketListeners();
    }
  }

  void markCallScreenOpen() => _isCallScreenOpen = true;
  void markCallScreenClosed() => _isCallScreenOpen = false;
  void markIncomingDialogOpen() => _isIncomingDialogOpen = true;
  void markIncomingDialogClosed() => _isIncomingDialogOpen = false;

  void minimizeCall() {
    if (_state == CallState.CALLING ||
        _state == CallState.RINGING ||
        _state == CallState.ACCEPTING ||
        _state == CallState.IN_CALL) {
      _isMinimized = true;
      _minimizedController.add(true);
      _log('📱 minimizeCall()');
    }
  }

  void expandCall() {
    _isMinimized = false;
    _minimizedController.add(false);
    _log('📱 expandCall()');
  }

  void hydrateIncomingCallFromPush({
    required String callId,
    required String callerId,
    required String callerName,
  }) {
    _log(
      '📞 hydrateIncomingCallFromPush() — callId=$callId callerId=$callerId callerName=$callerName',
    );

    final parsedCallId = int.tryParse(callId);
    final parsedCallerId = int.tryParse(callerId);
    if (parsedCallId == null || parsedCallerId == null) {
      _log('⚠️ hydrateIncomingCallFromPush() — invalid payload');
      return;
    }

    if (_state == CallState.CALLING ||
        _state == CallState.RINGING ||
        _state == CallState.ACCEPTING ||
        _state == CallState.IN_CALL) {
      _log('⚠️ hydrateIncomingCallFromPush() — already in call, state=$_state');
      return;
    }

    _resetTimer?.cancel();
    _hardReset();
    _currentCallId = parsedCallId;
    _remoteUserId = parsedCallerId;
    _remoteUserName = callerName;
    _lastEndReason = null;
    _lastCallEndTimestamp = null;
    _applyState(CallState.RINGING);
  }

  Future<void> _requestPermissions() async {}

  void _setupSocketListeners() {
    final socket = _socketService.socket;
    if (socket == null) {
      _log('🔌 _setupSocketListeners() — socket is null');
      return;
    }

    for (final event in const [
      'call:incoming',
      'call:accepted',
      'call:signal',
      'call:ended',
      'call:rejected',
    ]) {
      socket.off(event);
    }

    _socketService.onCallEvent('call:incoming', (data) {
      _log('📲 call:incoming — data=$data state=$_state');

      if (_isCallScreenOpen &&
          (_state == CallState.IDLE || _state == CallState.ENDED)) {
        markCallScreenClosed();
      }
      if (_isIncomingDialogOpen && _state != CallState.RINGING) {
        markIncomingDialogClosed();
      }

      if (_state == CallState.CALLING ||
          _state == CallState.RINGING ||
          _state == CallState.ACCEPTING ||
          _state == CallState.IN_CALL) {
        _log('⚠️ call:incoming ignored — active state=$_state');
        return;
      }
      if (_isCallScreenOpen || _isIncomingDialogOpen) {
        _log(
          '⚠️ call:incoming ignored — screen/dialog already open '
          '(screen=$_isCallScreenOpen dialog=$_isIncomingDialogOpen)',
        );
        return;
      }

      _resetTimer?.cancel();
      _hardReset();
      _currentCallId = data['callId'] as int?;
      _remoteUserId = data['callerId'] as int?;
      _remoteUserName = data['callerName'] as String? ?? 'Пользователь';
      _lastEndReason = null;
      _lastCallEndTimestamp = null;
      _applyState(CallState.RINGING);

      _incomingCallController.add({
        'callId': _currentCallId,
        'callerId': _remoteUserId,
        'callerName': _remoteUserName ?? 'Пользователь',
      });
    });

    _socketService.onCallEvent('call:accepted', (data) async {
      _log('📲 call:accepted — data=$data state=$_state');
      await CallRingtoneService().stopAllCallSounds();
      _resetTimer?.cancel();

      final acceptedCallId = data['callId'] as int?;
      if (_currentCallId == null && acceptedCallId != null) {
        _currentCallId = acceptedCallId;
      }

      _applyState(CallState.ACCEPTING);

      try {
        await _startPeerConnection(isCaller: true);
      } catch (e) {
        _log('🔴 call:accepted connect failed: $e');
        if (_currentCallId != null) {
          _socketService.sendCallEvent('call:end', {
            'callId': _currentCallId,
          });
        }
        await _endCall(reason: 'connection_failed');
      }
    });

    _socketService.onCallEvent('call:signal', (data) async {
      _log('📡 call:signal — type=${data['type']} state=$_state');

      if (data['callId'] != null && data['callId'] != _currentCallId) {
        _log('📡 call:signal ignored for another callId=${data['callId']}');
        return;
      }

      final type = data['type'] as String?;
      if (type == 'candidate') {
        final candidate = RTCIceCandidate(
          data['candidate'] as String?,
          data['sdpMid'] as String?,
          data['sdpMLineIndex'] as int?,
        );

        if (_peerConnection == null) {
          _pendingRemoteCandidates.add(candidate);
          _log('📡 candidate queued — peer not ready');
          return;
        }

        try {
          await _peerConnection!.addCandidate(candidate);
        } catch (e) {
          _pendingRemoteCandidates.add(candidate);
          _log('⚠️ addCandidate failed, queued for retry: $e');
        }
        return;
      }

      if (type == 'offer') {
        if (_peerConnection == null) {
          await _startPeerConnection(isCaller: false);
        }

        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(data['sdp'] as String?, 'offer'),
        );
        await _flushPendingRemoteCandidates();

        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        _socketService.sendCallSignal(_currentCallId!, {
          'type': 'answer',
          'sdp': answer.sdp,
        });
        _applyState(CallState.IN_CALL);
        _log('✅ answer sent');
        return;
      }

      if (type == 'answer') {
        if (_peerConnection == null) {
          _log('⚠️ answer received but peer connection is null');
          return;
        }

        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(data['sdp'] as String?, 'answer'),
        );
        await _flushPendingRemoteCandidates();
        _applyState(CallState.IN_CALL);
        _log('✅ answer applied');
        return;
      }

      _log('⚠️ call:signal unknown type=$type');
    });

    _socketService.onCallEvent('call:ended', (data) async {
      _log('📲 call:ended — data=$data state=$_state');
      if (_state == CallState.IDLE || _state == CallState.ENDED) {
        return;
      }

      await CallRingtoneService().stopAllCallSounds();
      final reason = data['reason'] as String?;
      await _endCall(reason: reason);
      if (reason == 'rejected') {
        _showSnackbar('Звонок отклонён');
      } else if (reason == 'expired') {
        _showSnackbar('Звонок уже завершён');
      }
    });

    _socketService.onCallEvent('call:rejected', (data) async {
      _log('📲 call:rejected — data=$data state=$_state');
      if (_state == CallState.CALLING ||
          _state == CallState.RINGING ||
          _state == CallState.ACCEPTING) {
        await CallRingtoneService().stopAllCallSounds();
        await _endCall(reason: 'rejected');
      }
    });

    _log('🔌 _setupSocketListeners() — listeners registered');
  }

  Future<void> startCall(int userId) async {
    _log('📞 startCall() — userId=$userId state=$_state');
    _resetTimer?.cancel();
    _lastEndReason = null;
    _lastCallEndTimestamp = null;

    if (_state != CallState.IDLE) {
      _hardReset();
    }

    _isMinimized = false;
    _minimizedController.add(false);
    await _callLogger.init();

    _remoteUserId = userId;
    _applyState(CallState.CALLING);
    _socketService.sendCallEvent('call:start', {
      'calleeId': userId,
    });
    await CallRingtoneService().playOutgoingRingbackTone();
  }

  Future<void> acceptCall() async {
    _log('✅ acceptCall() — callId=$_currentCallId state=$_state');

    if (_isAcceptingCall) {
      _log('⚠️ acceptCall() — already accepting');
      return;
    }

    _isAcceptingCall = true;
    try {
      await CallRingtoneService().stopAllCallSounds();
      _resetTimer?.cancel();

      final callId = _currentCallId;
      if (callId == null) {
        _log('⚠️ acceptCall() — callId is null');
        return;
      }

      _socketService.sendCallEvent('call:accept', {
        'callId': callId,
      });
      _applyState(CallState.ACCEPTING);

      try {
        await _startPeerConnection(isCaller: false);
      } catch (e) {
        _log('🔴 acceptCall() connect failed: $e');
        _socketService.sendCallEvent('call:end', {
          'callId': callId,
        });
        await _endCall(reason: 'connection_failed');
        rethrow;
      }
    } finally {
      _isAcceptingCall = false;
    }
  }

  Future<void> rejectCall() async {
    _log('❌ rejectCall() — callId=$_currentCallId state=$_state');
    await CallRingtoneService().stopAllCallSounds();
    _socketService.sendCallEvent('call:reject', {
      'callId': _currentCallId,
    });
    await _endCall(reason: 'rejected');
  }

  Future<void> endCall() async {
    _log('🔴 endCall() — callId=$_currentCallId state=$_state');
    if (_currentCallId != null) {
      _socketService.sendCallEvent('call:end', {
        'callId': _currentCallId,
      });
    }
    await _endCall(reason: 'ended_by_caller');
  }

  Future<void> _startPeerConnection({required bool isCaller}) async {
    if (_peerConnection != null) {
      _log('🔧 _startPeerConnection() — reusing existing peer');
      return;
    }

    final mediaConstraints = {
      'audio': true,
      'video': {
        'facingMode': _isFrontCamera ? 'user' : 'environment',
      },
    };

    try {
      _localStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localStreamController.add(_localStream);
    } catch (e) {
      _log('❌ getUserMedia failed: $e');
      rethrow;
    }

    try {
      _peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });
    } catch (e) {
      _log('❌ createPeerConnection failed: $e');
      rethrow;
    }

    for (final track in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    _peerConnection!.onIceCandidate = (candidate) {
      final callId = _currentCallId;
      if (callId == null || candidate.candidate == null) return;
      _socketService.sendCallSignal(callId, {
        'type': 'candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isEmpty) return;
      _remoteStream = event.streams.first;
      _remoteStreamController.add(_remoteStream);
      _log('✅ remote stream received');
    };

    _peerConnection!.onConnectionState = (state) {
      _log('🔗 PeerConnection state=$state');
      if ((state ==
                  RTCPeerConnectionState
                      .RTCPeerConnectionStateDisconnected ||
              state ==
                  RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
              state ==
                  RTCPeerConnectionState.RTCPeerConnectionStateClosed) &&
          (_state == CallState.CALLING ||
              _state == CallState.RINGING ||
              _state == CallState.ACCEPTING ||
              _state == CallState.IN_CALL)) {
        unawaited(_endCall(reason: 'peer_disconnected'));
      }
    };

    _peerConnection!.onIceConnectionState = (state) {
      _log('🧊 ICE state=$state');
      if ((state ==
                  RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
              state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
              state == RTCIceConnectionState.RTCIceConnectionStateClosed) &&
          (_state == CallState.CALLING ||
              _state == CallState.RINGING ||
              _state == CallState.ACCEPTING ||
              _state == CallState.IN_CALL)) {
        unawaited(_endCall(reason: 'peer_disconnected'));
      }
    };

    if (isCaller) {
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      _socketService.sendCallSignal(_currentCallId!, {
        'type': 'offer',
        'sdp': offer.sdp,
      });
      _log('✅ offer sent');
    }
  }

  Future<void> _flushPendingRemoteCandidates() async {
    if (_peerConnection == null || _pendingRemoteCandidates.isEmpty) return;
    final queued = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in queued) {
      try {
        await _peerConnection!.addCandidate(candidate);
      } catch (e) {
        _log('⚠️ queued candidate still failed: $e');
      }
    }
  }

  void toggleCamera() {
    _isFrontCamera = !_isFrontCamera;
    for (final track in _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      track.switchCamera();
    }
  }

  void toggleMic() {
    _isMicOn = !_isMicOn;
    for (final track in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = _isMicOn;
    }
  }

  void toggleCameraVideo() {
    _isCameraOn = !_isCameraOn;
    for (final track in _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = _isCameraOn;
    }
  }

  void handleConnectionLost() {
    if (_state == CallState.CALLING ||
        _state == CallState.RINGING ||
        _state == CallState.ACCEPTING ||
        _state == CallState.IN_CALL) {
      unawaited(_endCall(reason: 'peer_disconnected'));
    }
  }

  Future<void> _endCall({String? reason}) async {
    if (_state == CallState.ENDED || _state == CallState.IDLE) {
      _log('🔴 _endCall() skipped — state=$_state');
      return;
    }
    if (_isEndingCall) {
      _log('🔴 _endCall() skipped — end already in progress');
      return;
    }

    _isEndingCall = true;
    _log('🔴 _endCall() — reason=$reason state=$_state');

    _lastEndReason = reason;
    _lastCallEndTimestamp = DateTime.now().millisecondsSinceEpoch;
    _isAcceptingCall = false;

    await CallRingtoneService().stopAllCallSounds();
    _disposePeerResources();

    _localStreamController.add(null);
    _remoteStreamController.add(null);
    _isMinimized = false;
    _isCallScreenOpen = false;
    _isIncomingDialogOpen = false;
    _minimizedController.add(false);

    _applyState(CallState.ENDED);
    await _callLogger.close();

    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), _hardReset);
  }

  void _disposePeerResources() {
    try {
      _peerConnection?.onIceCandidate = null;
      _peerConnection?.onTrack = null;
      _peerConnection?.onConnectionState = null;
      _peerConnection?.onIceConnectionState = null;
      _peerConnection?.close();
    } catch (e) {
      _log('⚠️ peer cleanup failed: $e');
    }

    try {
      for (final track in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
        track.stop();
      }
    } catch (e) {
      _log('⚠️ local stream cleanup failed: $e');
    }

    _peerConnection = null;
    _localStream = null;
    _remoteStream = null;
    _pendingRemoteCandidates.clear();
  }

  void _hardReset() {
    _log('🔄 _hardReset()');
    _resetTimer?.cancel();
    _resetTimer = null;
    _disposePeerResources();
    unawaited(CallRingtoneService().stopAllCallSounds());

    _currentCallId = null;
    _remoteUserId = null;
    _remoteUserName = null;
    _isCameraOn = true;
    _isMicOn = true;
    _isFrontCamera = true;
    _isCallScreenOpen = false;
    _isIncomingDialogOpen = false;
    _isMinimized = false;
    _isAcceptingCall = false;
    _isEndingCall = false;
    _lastEndReason = null;

    _localStreamController.add(null);
    _remoteStreamController.add(null);
    _minimizedController.add(false);
    _applyState(CallState.IDLE);
  }

  void hardReset() {
    _hardReset();
  }

  void _applyState(CallState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void _showSnackbar(String message) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  void dispose() {
    _connectionSubscription?.cancel();
    _stateController.close();
    _localStreamController.close();
    _remoteStreamController.close();
    _incomingCallController.close();
    _minimizedController.close();
  }

  void _log(String message) {
    print('[CALL_SERVICE] $message');
    _callLogger.log('CallService', message);
  }
}
