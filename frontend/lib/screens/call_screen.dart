import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/call_service.dart';
import '../services/call_logger.dart';

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
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  Offset _pipOffset = const Offset(20, 80);
  bool _hasNavigatedAway = false;
  int _remoteViewVersion = 0;

  // Stream-подписки для корректной отмены в dispose()
  StreamSubscription<MediaStream?>? _localStreamSub;
  StreamSubscription<MediaStream?>? _remoteStreamSub;

  // Отложенная задача закрытия экрана (заменяет Timer)
  Timer? _closeCallScreenTimer;

  // Флаг: было ли уже запланировано закрытие экрана после ENDED
  // Предотвращает повторный вызов _closeCallScreen при ребилдах StreamBuilder
  bool _closeScheduled = false;

  @override
  void initState() {
    super.initState();
    _log('initState() — userId=${widget.userId}, isIncoming=${widget.isIncoming}, state=${_callService.state}');
    _callService.markCallScreenOpen();

    if (_callService.isMinimized) {
      _callService.expandCall();
    }

    _initRenderers();

    if (!widget.isIncoming) {
      if (_callService.state == CallState.RINGING) {
        _log('initState() — isIncoming=false but state=RINGING, treating as incoming');
      } else if (_callService.state == CallState.CALLING ||
                 _callService.state == CallState.ACCEPTING ||
                 _callService.state == CallState.IN_CALL) {
        _log('initState() — already in call (state=${_callService.state})');
      } else {
        _log('initState() — starting outgoing call to userId=${widget.userId}');
        _callService.startCall(widget.userId);
      }
    }
  }

  Future<void> _initRenderers() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
    } catch (e) {
      _log('_initRenderers() — renderer init FAILED: $e');
    }

    if (!mounted) return;

    // Немедленно подхватываем уже существующие потоки (важно для minimize→expand)
    final currentLocal = _callService.currentLocalStream;
    if (currentLocal != null) {
      _localRenderer.srcObject = currentLocal;
      if (mounted) setState(() {});
    }

    if (!mounted) return;

    final currentRemote = _callService.currentRemoteStream;
    if (currentRemote != null) {
      _remoteRenderer.srcObject = null;
      _remoteRenderer.srcObject = currentRemote;
      _remoteViewVersion++;
      if (mounted) setState(() {});
    }

    if (!mounted) return;

    // Подписываемся на stream-события для будущих обновлений
    _localStreamSub = _callService.localStream.listen((stream) {
      _localRenderer.srcObject = stream;
      if (mounted) setState(() {});
    });

    _remoteStreamSub = _callService.remoteStream.listen((stream) {
      if (stream != null && identical(_remoteRenderer.srcObject, stream)) {
        _remoteRenderer.srcObject = null;
      }
      _remoteRenderer.srcObject = stream;
      _remoteViewVersion++;
      if (mounted) setState(() {});
    });
  }

  /// Единый метод закрытия экрана звонка.
  /// Проверяет _hasNavigatedAway атомарно, чтобы избежать двойного pop().
  void _closeCallScreen({Duration delay = Duration.zero}) {
    if (_hasNavigatedAway) return;
    _hasNavigatedAway = true;
    _closeScheduled = false;

    // Отменяем предыдущую отложенную задачу, если была
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
      _log('_closeCallScreen() ? delayed close in ${delay.inMilliseconds}ms');
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

  Widget _buildRemoteStage() {
    if (_remoteRenderer.srcObject != null) {
      return RTCVideoView(
        _remoteRenderer,
        key: ValueKey('remote-video-$_remoteViewVersion'),
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.person,
              color: Colors.white54,
              size: 72,
            ),
            const SizedBox(height: 16),
            Text(
              _callService.remoteUserName ?? widget.userName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                color: Colors.white70,
                strokeWidth: 2.5,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Подключаем видео...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _log('dispose() — state=${_callService.state}');

    // Отменяем stream-подписки
    _localStreamSub?.cancel();
    _remoteStreamSub?.cancel();

    // Отменяем отложенную задачу закрытия
    _closeCallScreenTimer?.cancel();
    _closeCallScreenTimer = null;

    _callService.markCallScreenClosed();
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentState = _callService.state;
    final currentReason = _callService.lastEndReason;

    // ended_by_caller: закрываем немедленно, без единого лишнего фрейма
    if (currentState == CallState.ENDED &&
        currentReason == 'ended_by_caller' &&
        !_hasNavigatedAway) {
      _log('[ENDED] ended_by_caller — immediate close');
      // Сбрасываем renderers, чтобы не было старого кадра перед закрытием
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
      _closeCallScreen();
    }

    // Для остальных ENDED-причин сбрасываем renderers при первом обнаружении
    if (currentState == CallState.ENDED &&
        currentReason != 'ended_by_caller' &&
        !_hasNavigatedAway) {
      if (_localRenderer.srcObject != null || _remoteRenderer.srcObject != null) {
        _localRenderer.srcObject = null;
        _remoteRenderer.srcObject = null;
        _log('[ENDED] renderers cleared for reason=$currentReason');
      }
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
          // markCallScreenClosed ПОСЛЕ pop, чтобы isCallScreenOpen
          // оставался true до фактического закрытия экрана.
          // Это предотвращает гонку, когда входящий звонок может
          // быть принят между markCallScreenClosed() и Navigator.pop().
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

            // Защита: если экран уже закрывается (ENDED обработан),
            // игнорируем IDLE из _hardReset, чтобы не мелькнул fallback
            if (state == CallState.IDLE && _hasNavigatedAway) {
              return const SizedBox.shrink();
            }

            final effectiveIncoming =
                widget.isIncoming || currentState == CallState.RINGING;
            return Stack(
              children: [
                // Remote video (full screen) — показываем только в активных состояниях
                if (state == CallState.CALLING ||
                    state == CallState.RINGING ||
                    state == CallState.ACCEPTING ||
                    state == CallState.IN_CALL)
                  _buildRemoteStage(),
                // Local video (PiP) — показываем только в активных состояниях
                if (state == CallState.CALLING ||
                    state == CallState.RINGING ||
                    state == CallState.ACCEPTING ||
                    state == CallState.IN_CALL)
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
                // ENDED UI — показываем по центру, перекрывая всё
                if (state == CallState.ENDED) _buildEndedUI(state),
                // Controls для активных состояний
                if (state == CallState.CALLING ||
                    state == CallState.ACCEPTING ||
                    state == CallState.IN_CALL)
                  Positioned(
                    bottom: 50,
                    left: 0,
                    right: 0,
                    child: _buildControls(state),
                  ),
                // Incoming call UI — только если state реально RINGING
                if (state == CallState.RINGING) _buildIncomingCallUI(),
                // Fallback UI — только если state=IDLE, но экран открыт как входящий
                if (state == CallState.IDLE && effectiveIncoming)
                  _buildIdleFallback(),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Единый метод для UI завершения звонка (ENDED).
  /// Показывается по центру экрана, перекрывая старые видео-кадры.
  /// Запускает отложенное закрытие экрана (кроме ended_by_caller).
  Widget _buildEndedUI(CallState state) {
    final reason = _callService.lastEndReason;

    // ended_by_caller обрабатывается в build() — здесь только остальные причины
    if (reason == 'ended_by_caller') {
      return const SizedBox.shrink();
    }

    // Запускаем отложенное закрытие ТОЛЬКО один раз
    if (!_hasNavigatedAway && !_closeScheduled) {
      _closeScheduled = true;
      Duration delay;
      if (reason == 'no_answer') {
        delay = const Duration(milliseconds: 1500);
      } else if (reason == 'peer_disconnected') {
        delay = const Duration(milliseconds: 1000);
      } else {
        // rejected, expired, и любые другие — 0.8 сек
        delay = const Duration(milliseconds: 800);
      }
      _log('[ENDED] reason=$reason, auto-close in ${delay.inMilliseconds}ms');
      _closeCallScreen(delay: delay);
    }

    // Определяем иконку и текст для каждой причины
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

    // Единый шаблон для всех ENDED-причин — по центру экрана
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

    if (state == CallState.ACCEPTING) {
      return Column(
        children: [
          const Text(
            'Подключение...',
            style: TextStyle(color: Colors.white, fontSize: 18),
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

  Widget _buildIncomingCallUI() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Входящий звонок от ${_callService.remoteUserName ?? widget.userName}',
              style: const TextStyle(color: Colors.white, fontSize: 24),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  onPressed: () {
                    _callService.rejectCall();
                  },
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.call_end),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Fallback UI для случая, когда state=IDLE, но экран открыт как входящий/исходящий.
  /// Показывает имя собеседника, статус "Подготовка..." и кнопку закрыть.
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

  /// Пишет лог одновременно в print (adb) и в файл (CallLogger)
  void _log(String message) {
    print('[CALL_SCREEN] $message');
    _callLogger.log('CallScreen', message);
  }
}

