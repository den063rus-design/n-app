import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/call_service.dart';
import '../services/call_logger.dart';

class CallScreen extends StatefulWidget {
  final int userId;
  final String userName;
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.isIncoming = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallService _callService = CallService();
  final CallLogger _callLogger = CallLogger();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  Offset _pipOffset = const Offset(20, 80);

  @override
  void initState() {
    super.initState();
    _log('🟢🟢🟢 initState() — userId=${widget.userId}, userName=${widget.userName}, isIncoming=${widget.isIncoming}');
    _log('🟢 initState() — CallService state=${_callService.state}, callId=${_callService.currentCallId}');
    _log('🟢 initState() — marking call screen as open');
    _callService.markCallScreenOpen();
    _initRenderers();
    // init() вызывается глобально в app.dart, здесь не нужен

    if (!widget.isIncoming) {
      _log('🟢 initState() — Starting outgoing call to userId=${widget.userId}');
      _callService.startCall(widget.userId);
    } else {
      _log('🟢 initState() — Incoming call screen — waiting for user to accept');
      _log('🟢 initState() — remoteUserId=${_callService.remoteUserId}, remoteUserName=${_callService.remoteUserName}');
    }
  }

  Future<void> _initRenderers() async {
    _log('🎬 _initRenderers() — initializing local and remote renderers');
    _log('🎬 _initRenderers() — _localRenderer.initialize()...');
    try {
      await _localRenderer.initialize();
      _log('✅ _initRenderers() — Local renderer initialized');
    } catch (e) {
      _log('❌ _initRenderers() — Local renderer init FAILED: $e');
    }
    _log('🎬 _initRenderers() — _remoteRenderer.initialize()...');
    try {
      await _remoteRenderer.initialize();
      _log('✅ _initRenderers() — Remote renderer initialized');
    } catch (e) {
      _log('❌ _initRenderers() — Remote renderer init FAILED: $e');
    }
    _log('🎬 _initRenderers() — Both renderers initialized, subscribing to streams');

    _callService.localStream.listen((stream) {
      _log('📥📥📥 Local stream event from CallService — stream=$stream');
      if (stream != null) {
        _log('📥 Local stream received — assigning to _localRenderer.srcObject');
        _log('    - Stream id: ${stream.id}');
        _log('    - Video tracks: ${stream.getVideoTracks().length}');
        _log('    - Audio tracks: ${stream.getAudioTracks().length}');
        for (var t in stream.getVideoTracks()) {
          _log('      video track: ${t.id}, enabled: ${t.enabled}, kind: ${t.kind}');
        }
        for (var t in stream.getAudioTracks()) {
          _log('      audio track: ${t.id}, enabled: ${t.enabled}, kind: ${t.kind}');
        }
        _localRenderer.srcObject = stream;
        _log('✅ _localRenderer.srcObject set — renderer now has video');
        setState(() {});
      } else {
        _log('⚠️⚠️⚠️ Local stream is NULL — nothing to assign to renderer');
        _log('⚠️ This is expected if _startPeerConnection was never called');
      }
    });

    _callService.remoteStream.listen((stream) {
      _log('📥📥📥 Remote stream event from CallService — stream=$stream');
      if (stream != null) {
        _log('📥 Remote stream received — assigning to _remoteRenderer.srcObject');
        _log('    - Stream id: ${stream.id}');
        _log('    - Video tracks: ${stream.getVideoTracks().length}');
        _log('    - Audio tracks: ${stream.getAudioTracks().length}');
        for (var t in stream.getVideoTracks()) {
          _log('      video track: ${t.id}, enabled: ${t.enabled}, kind: ${t.kind}');
        }
        for (var t in stream.getAudioTracks()) {
          _log('      audio track: ${t.id}, enabled: ${t.enabled}, kind: ${t.kind}');
        }
        _remoteRenderer.srcObject = stream;
        _log('✅ _remoteRenderer.srcObject set — renderer now has video');
        setState(() {});
      } else {
        _log('⚠️⚠️⚠️ Remote stream is NULL — nothing to assign to renderer');
        _log('⚠️ This is expected if remote peer never connected');
      }
    });
    _log('🎬 _initRenderers() — stream subscriptions set up');
  }

  @override
  void dispose() {
    _log('🔴🔴🔴 dispose() — cleaning up CallScreen');
    _log('🔴 dispose() — CallService state=${_callService.state}, callId=${_callService.currentCallId}');
    _log('🔴 dispose() — _localRenderer.srcObject=${_localRenderer.srcObject?.id}');
    _log('🔴 dispose() — _remoteRenderer.srcObject=${_remoteRenderer.srcObject?.id}');
    _callService.markCallScreenClosed();
    _log('🔴 dispose() — disposing local renderer');
    _localRenderer.dispose();
    _log('🔴 dispose() — disposing remote renderer');
    _remoteRenderer.dispose();
    _log('🔴 dispose() — super.dispose()');
    super.dispose();
    _log('🔴 dispose() — done');
  }

  @override
  Widget build(BuildContext context) {
    _log('🖼️ build() called');
    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<CallState>(
        stream: _callService.stateStream,
        builder: (context, snapshot) {
          final state = snapshot.data ?? CallState.IDLE;
          _log('🖼️ build() — state=$state');
          _log('🖼️ build() — _localRenderer.srcObject=${_localRenderer.srcObject?.id ?? 'null'}');
          _log('🖼️ build() — _remoteRenderer.srcObject=${_remoteRenderer.srcObject?.id ?? 'null'}');
          _log('🖼️ build() — _localRenderer.initialize()=${_localRenderer.initialize() != null ? 'called' : '?'}');
          return Stack(
            children: [
              // Remote video (full screen)
              RTCVideoView(
                _remoteRenderer,
                objectFit:
                    RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
              // Local video (PiP)
              Positioned(
                left: _pipOffset.dx,
                top: _pipOffset.dy,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _pipOffset = Offset(
                        (_pipOffset.dx + details.delta.dx)
                            .clamp(12.0, MediaQuery.of(context).size.width - 132.0)
                            .toDouble(),
                        (_pipOffset.dy + details.delta.dy)
                            .clamp(80.0, MediaQuery.of(context).size.height - 232.0)
                            .toDouble(),
                      );
                    });
                  },
                  child: Container(
                    width: 120,
                    height: 180,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white, width: 2),
                      color: Colors.black87,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          RTCVideoView(
                            _localRenderer,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
                            mirror: true,
                          ),
                          Positioned(
                            left: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _callService.isCameraOn ? 'Видео' : 'Аудио',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Controls
              Positioned(
                bottom: 50,
                left: 0,
                right: 0,
                child: _buildControls(state),
              ),
              // Incoming call UI
              if (state == CallState.RINGING) _buildIncomingCallUI(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildControls(CallState state) {
    if (state == CallState.CALLING) {
      return Column(
        children: [
          const Text(
            'Звонок...',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 20),
          FloatingActionButton(
            onPressed: () {
              _callService.endCall();
              Navigator.pop(context);
            },
            backgroundColor: Colors.red,
            child: const Icon(Icons.call_end),
          ),
        ],
      );
    }

    if (state == CallState.IN_CALL) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Микрофон
          StreamBuilder<CallState>(
            stream: _callService.stateStream,
            builder: (context, snapshot) {
              return FloatingActionButton(
                onPressed: () {
                  _callService.toggleMic();
                  setState(() {});
                },
                backgroundColor:
                    _callService.isMicOn ? Colors.white : Colors.red,
                child: Icon(
                  _callService.isMicOn ? Icons.mic : Icons.mic_off,
                  color: Colors.black,
                ),
              );
            },
          ),
          // Завершить
          FloatingActionButton(
            onPressed: () {
              _callService.endCall();
              Navigator.pop(context);
            },
            backgroundColor: Colors.red,
            child: const Icon(Icons.call_end),
          ),
          // Камера
          StreamBuilder<CallState>(
            stream: _callService.stateStream,
            builder: (context, snapshot) {
              return FloatingActionButton(
                onPressed: () {
                  _callService.toggleCameraVideo();
                  setState(() {});
                },
                backgroundColor:
                    _callService.isCameraOn ? Colors.white : Colors.red,
                child: Icon(
                  _callService.isCameraOn
                      ? Icons.videocam
                      : Icons.videocam_off,
                  color: Colors.black,
                ),
              );
            },
          ),
          // Переключить камеру
          FloatingActionButton(
            onPressed: () {
              _callService.toggleCamera();
              setState(() {});
            },
            backgroundColor: Colors.white,
            child: const Icon(Icons.flip_camera_android, color: Colors.black),
          ),
        ],
      );
    }

    if (state == CallState.ENDED) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    }

    return const SizedBox.shrink();
  }

  Widget _buildIncomingCallUI() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Входящий звонок...',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  onPressed: () {
                    _callService.rejectCall();
                    Navigator.pop(context);
                  },
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.call_end),
                ),
                FloatingActionButton(
                  onPressed: () {
                    _callService.acceptCall();
                    setState(() {});
                  },
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.call),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Пишет лог одновременно в print (adb) и в файл (CallLogger)
  void _log(String message) {
    print('[CALL_SCREEN] $message');
    _callLogger.log('CallScreen', message);
  }
}
