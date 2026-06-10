import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/call_service.dart';

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
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  Offset _pipOffset = const Offset(20, 80);

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _callService.init();

    if (!widget.isIncoming) {
      _callService.startCall(widget.userId);
    }
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _callService.localStream.listen((stream) {
      if (stream != null) {
        _localRenderer.srcObject = stream;
      }
    });

    _callService.remoteStream.listen((stream) {
      if (stream != null) {
        _remoteRenderer.srcObject = stream;
      }
    });
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<CallState>(
        stream: _callService.stateStream,
        builder: (context, snapshot) {
          final state = snapshot.data ?? CallState.IDLE;
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
}
