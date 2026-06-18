import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../services/call_service.dart';
import '../services/call_logger.dart';
import '../services/call_session.dart';

class CallScreen extends StatefulWidget {
  final int userId;
  final String userName;
  final bool isIncoming;
  final String from;

  const CallScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.isIncoming = false,
    this.from = 'chat',
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallService _callService = CallService();
  final CallLogger _callLogger = CallLogger();
  Offset _pipOffset = const Offset(20, 80);
  bool _hasNavigatedAway = false;

  // Отложенная задача закрытия экрана (заменяет Timer)
  Timer? _closeCallScreenTimer;

  // Флаг: было ли уже запланировано закрытие экрана после ENDED
  bool _closeScheduled = false;

  // Подписки на CallSession
  VoidCallback? _localVideoListener;
  VoidCallback? _remoteVideoListener;
  VoidCallback? _connectionStateListener;

  @override
  void initState() {
    super.initState();
    _log('initState() — userId=${widget.userId}, isIncoming=${widget.isIncoming}, state=${_callService.state}');
    _callService.markCallScreenOpen();

    if (_callService.isMinimized) {
      _callService.expandCall();
    }

    if (!widget.isIncoming) {
      if (_callService.state == CallState.RINGING) {
        _log('initState() — isIncoming=false but state=RINGING, treating as incoming');
      } else if (_callService.state == CallState.CALLING ||
                 _callService.state == CallState.IN_CALL) {
        _log('initState() — already in call (state=${_callService.state})');
      } else {
        _log('initState() — starting outgoing call to userId=${widget.userId}');
        _callService.startCall(widget.userId);
      }
    }

    // Подписываемся на изменения видео-треков из CallSession
    _setupLiveKitListeners();
  }

  void _setupLiveKitListeners() {
    final session = _callService.currentSession;

    _localVideoListener = () {
      if (mounted) setState(() {});
    };
    _connectionStateListener = () {
      if (mounted) setState(() {});
    };
    _remoteVideoListener = () {
      if (mounted) setState(() {});
    };

    // Если сессия уже существует — подписываемся сразу
    if (session != null) {
      session.localVideoTrack.addListener(_localVideoListener!);
      session.remoteVideoTrack.addListener(_remoteVideoListener!);
      session.connectionState.addListener(_connectionStateListener!);
    }
  }

  /// Единый метод закрытия экрана звонка.
  void _closeCallScreen({Duration delay = Duration.zero}) {
    if (_hasNavigatedAway) return;
    _hasNavigatedAway = true;
    _closeScheduled = false;

    _closeCallScreenTimer?.cancel();
    _closeCallScreenTimer = null;

    if (delay == Duration.zero) {
      _log('_closeCallScreen() — immediate close');
      _callService.markCallScreenClosed();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.pop(context);
        }
      });
    } else {
      _log('_closeCallScreen() — delayed close in ${delay.inMilliseconds}ms');
      _closeCallScreenTimer = Timer(delay, () {
        if (mounted) {
          _callService.markCallScreenClosed();
          if (Navigator.of(context).canPop()) {
            Navigator.pop(context);
          }
        }
        _closeCallScreenTimer = null;
      });
    }
  }

  @override
  void dispose() {
    _log('dispose() — state=${_callService.state}');

    _closeCallScreenTimer?.cancel();
    _closeCallScreenTimer = null;

    // Отписываемся от CallSession
    final session = _callService.currentSession;
    if (session != null) {
      if (_localVideoListener != null) {
        session.localVideoTrack.removeListener(_localVideoListener!);
      }
      if (_remoteVideoListener != null) {
        session.remoteVideoTrack.removeListener(_remoteVideoListener!);
      }
      if (_connectionStateListener != null) {
        session.connectionState.removeListener(_connectionStateListener!);
      }
    }

    _callService.markCallScreenClosed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentState = _callService.state;
    final currentReason = _callService.lastEndReason;

    // ended_by_caller: закрываем немедленно
    if (currentState == CallState.ENDED &&
        currentReason == 'ended_by_caller' &&
        !_hasNavigatedAway) {
      _log('[ENDED] ended_by_caller — immediate close');
      _closeCallScreen();
    }

    return PopScope(
      canPop: currentState == CallState.ENDED ||
          currentState == CallState.IDLE,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final state = currentState;
        if (state == CallState.CALLING ||
            state == CallState.RINGING ||
            state == CallState.ACCEPTING ||
            state == CallState.IN_CALL) {
          _log('PopScope — minimizing call (state=$state)');
          _callService.minimizeCall();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _callService.markCallScreenClosed();
          });
          Navigator.of(context).pop();
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _callService.markCallScreenClosed();
          });
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: StreamBuilder<CallState>(
          stream: _callService.stateStream,
          initialData: currentState,
          builder: (context, snapshot) {
            final state = snapshot.data ?? currentState;

            if (state == CallState.IDLE && _hasNavigatedAway) {
              return const SizedBox.shrink();
            }

            final effectiveIncoming =
                widget.isIncoming || currentState == CallState.RINGING;
            return Stack(
              children: [
                // Remote video (full screen)
                if (state == CallState.CALLING ||
                    state == CallState.RINGING ||
                    state == CallState.ACCEPTING ||
                    state == CallState.IN_CALL)
                  _buildRemoteVideo(),
                // Local video (PiP)
                if (state == CallState.CALLING ||
                    state == CallState.RINGING ||
                    state == CallState.ACCEPTING ||
                    state == CallState.IN_CALL)
                  _buildLocalVideo(),
                // ENDED UI
                if (state == CallState.ENDED) _buildEndedUI(state),
                // Controls
                if (state == CallState.CALLING ||
                    state == CallState.ACCEPTING ||
                    state == CallState.IN_CALL)
                  Positioned(
                    bottom: 50,
                    left: 0,
                    right: 0,
                    child: _buildControls(state),
                  ),
                // Fallback UI
                if (state == CallState.IDLE && effectiveIncoming)
                  _buildIdleFallback(),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Remote video через LiveKit VideoTrackRenderer
  Widget _buildRemoteVideo() {
    final session = _callService.currentSession;
    final remoteTrack = session?.remoteVideoTrack.value;
    final connState = session?.connectionState.value ?? LiveKitConnectionState.disconnected;
    final hasRemoteParticipant = session?.remoteParticipant.value != null;
    final callState = _callService.state;

    _log('_buildRemoteVideo — remoteTrack=${remoteTrack != null}, connState=$connState, hasRemoteParticipant=$hasRemoteParticipant, callState=$callState');

    if (remoteTrack != null) {
      _log('_buildRemoteVideo — RENDERING remote video track');
      return VideoTrackRenderer(
        remoteTrack,
        fit: VideoViewFit.cover,
      );
    }

    // Fallback — показываем имя собеседника, пока нет видео
    String statusText;
    if (connState == LiveKitConnectionState.connecting) {
      statusText = 'Подключение...';
    } else if (connState == LiveKitConnectionState.connected && !hasRemoteParticipant) {
      statusText = 'Ожидание собеседника...';
    } else if (connState == LiveKitConnectionState.connected && hasRemoteParticipant) {
      statusText = 'Собеседник подключился, ожидание видео...';
    } else if (connState == LiveKitConnectionState.error) {
      statusText = 'Ошибка подключения';
    } else if (connState == LiveKitConnectionState.disconnected) {
      statusText = 'Нет подключения';
    } else if (connState == LiveKitConnectionState.reconnecting) {
      statusText = 'Переподключение...';
    } else {
      statusText = 'Ожидание собеседника...';
    }

    _log('_buildRemoteVideo — FALLBACK: statusText="$statusText" connState=$connState hasRemoteParticipant=$hasRemoteParticipant remoteTrack=$remoteTrack');

    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person, color: Colors.white54, size: 80),
            const SizedBox(height: 16),
            Text(
              _callService.remoteUserName ?? widget.userName,
              style: const TextStyle(color: Colors.white, fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              statusText,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  /// Local video (PiP) через LiveKit VideoViewWidget
  Widget _buildLocalVideo() {
    final session = _callService.currentSession;
    final localTrack = session?.localVideoTrack.value;
    return Positioned(
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
                if (localTrack != null)
                  VideoTrackRenderer(
                    localTrack,
                    fit: VideoViewFit.cover,
                    mirrorMode: VideoViewMirrorMode.mirror,
                  )
                else
                  const Center(
                    child: Icon(Icons.person, color: Colors.white54, size: 40),
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
    );
  }

  Widget _buildEndedUI(CallState state) {
    final reason = _callService.lastEndReason;

    if (reason == 'ended_by_caller') {
      return const SizedBox.shrink();
    }

    if (!_hasNavigatedAway && !_closeScheduled) {
      _closeScheduled = true;
      Duration delay;
      if (reason == 'no_answer') {
        delay = const Duration(milliseconds: 1500);
      } else if (reason == 'peer_disconnected') {
        delay = const Duration(milliseconds: 1000);
      } else {
        delay = const Duration(milliseconds: 800);
      }
      _log('[ENDED] reason=$reason, auto-close in ${delay.inMilliseconds}ms');
      _closeCallScreen(delay: delay);
    }

    IconData icon;
    String text;
    switch (reason) {
      case 'no_answer':
        icon = Icons.phone_missed;
        text = 'Абонент не ответил';
        break;
      case 'peer_disconnected':
        icon = Icons.wifi_off;
        text = 'Собеседник отключился';
        break;
      case 'rejected':
        icon = Icons.call_end;
        text = 'Звонок отклонён';
        break;
      case 'expired':
        icon = Icons.timer_off;
        text = 'Звонок уже завершён';
        break;
      default:
        icon = Icons.call_end;
        text = 'Звонок завершён';
        break;
    }

    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white70, size: 64),
            const SizedBox(height: 16),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 32),
            FloatingActionButton(
              onPressed: () {
                if (mounted) {
                  _closeCallScreen();
                }
              },
              backgroundColor: Colors.red,
              child: const Icon(Icons.call_end),
            ),
          ],
        ),
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
          FloatingActionButton(
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
          ),
          // Завершить
          FloatingActionButton(
            onPressed: () {
              _callService.endCall();
            },
            backgroundColor: Colors.red,
            child: const Icon(Icons.call_end),
          ),
          // Камера
          FloatingActionButton(
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

    return const SizedBox.shrink();
  }

  Widget _buildIdleFallback() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _callService.remoteUserName ?? widget.userName,
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Подготовка звонка...',
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(height: 48),
            FloatingActionButton(
              onPressed: () {
                _callService.endCall();
              },
              backgroundColor: Colors.red,
              child: const Icon(Icons.call_end),
            ),
          ],
        ),
      ),
    );
  }

  void _log(String message) {
    print('[CALL_SCREEN] $message');
    _callLogger.log('CallScreen', message);
  }
}
