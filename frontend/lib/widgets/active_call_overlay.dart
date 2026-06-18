import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/call_service.dart';
import '../services/call_logger.dart';

/// Маленькое плавающее окно активного звонка поверх приложения.
///
/// Показывается, когда звонок свёрнут (isMinimized == true).
/// Содержит:
/// - видео/аватар собеседника
/// - имя собеседника
/// - маленькую красную кнопку завершения звонка
/// - draggable
///
/// По тапу открывает обратно fullscreen CallScreen.
class ActiveCallOverlay extends StatefulWidget {
  /// Колбэк, вызываемый при тапе на overlay для открытия fullscreen CallScreen
  final VoidCallback? onTap;

  const ActiveCallOverlay({super.key, this.onTap});

  @override
  State<ActiveCallOverlay> createState() => _ActiveCallOverlayState();
}

class _ActiveCallOverlayState extends State<ActiveCallOverlay> {
  final CallService _callService = CallService();
  final CallLogger _callLogger = CallLogger();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  StreamSubscription<MediaStream?>? _remoteStreamSub;
  StreamSubscription<CallState>? _stateSub;
  StreamSubscription<bool>? _minimizedSub;

  Offset _position = const Offset(16, 100);
  bool _visible = false;

  bool _shouldShowOverlay(CallState state, bool isMinimized) {
    // Guard: не показываем overlay в терминальных состояниях
    if (state == CallState.ENDED || state == CallState.IDLE) return false;
    return isMinimized &&
        (state == CallState.CALLING ||
            state == CallState.RINGING ||
            state == CallState.ACCEPTING ||
            state == CallState.IN_CALL);
  }

  void _updateVisibility(CallState state, bool isMinimized) {
    final shouldShow = _shouldShowOverlay(state, isMinimized);
    if (shouldShow != _visible) {
      setState(() {
        _visible = shouldShow;
      });
      if (shouldShow) {
        // Восстанавливаем remoteRenderer, если был сброшен
        if (_remoteRenderer.srcObject == null) {
          final currentRemote = _callService.currentRemoteStream;
          if (currentRemote != null) {
            _remoteRenderer.srcObject = currentRemote;
          }
        }
        _log('overlay shown');
      } else {
        // При скрытии overlay отвязываем remoteRenderer,
        // чтобы при новом звонке не мелькнул старый кадр
        _remoteRenderer.srcObject = null;
        _log('overlay hidden');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _initRenderer();
    _subscribe();
  }

  Future<void> _initRenderer() async {
    try {
      await _remoteRenderer.initialize();

      final currentRemote = _callService.currentRemoteStream;
      if (currentRemote != null) {
        _remoteRenderer.srcObject = currentRemote;
        if (mounted) setState(() {});
      }
    } catch (e) {
      _log('❌ Remote renderer init FAILED: $e');
    }
  }

  void _subscribe() {
    _remoteStreamSub = _callService.remoteStream.listen((stream) {
      if (!mounted) return;
      _remoteRenderer.srcObject = stream;
      setState(() {});
    });

    _stateSub = _callService.stateStream.listen((state) {
      if (!mounted) return;
      _updateVisibility(state, _callService.isMinimized);
    });

    _minimizedSub = _callService.minimizedStream.listen((isMinimized) {
      if (!mounted) return;
      _updateVisibility(_callService.state, isMinimized);
    });

    // Синхронизируем _visible с текущим состоянием и вызываем setState,
    // чтобы build() отреагировал на начальное значение
    _visible = _shouldShowOverlay(_callService.state, _callService.isMinimized);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _remoteStreamSub?.cancel();
    _stateSub?.cancel();
    _minimizedSub?.cancel();
    _remoteRenderer.srcObject = null;
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _log(String message) {
    print('[CALL_OVERLAY] $message');
    _callLogger.log('ActiveCallOverlay', message);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (_position.dx + details.delta.dx)
                  .clamp(0.0, screenWidth - 140.0)
                  .toDouble(),
              (_position.dy + details.delta.dy)
                  .clamp(0.0, screenHeight - 200.0)
                  .toDouble(),
            );
          });
        },
        onTap: () {
          _callService.expandCall();
          widget.onTap?.call();
        },
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          color: Colors.transparent,
          child: Container(
            width: 130,
            height: 190,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white, width: 2),
              color: Colors.black87,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  // Remote video
                  if (_remoteRenderer.srcObject != null)
                    RTCVideoView(
                      _remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  else
                    // Fallback — аватар/имя, если видео нет
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.person,
                            color: Colors.white70,
                            size: 40,
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              _callService.remoteUserName ?? 'Звонок',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white54,
                              strokeWidth: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Верхняя полоска с именем
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Text(
                        _callService.remoteUserName ?? 'Звонок',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                  // Кнопка завершения звонка
                  Positioned(
                    bottom: 6,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: () {
                          _callService.endCall();
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.call_end,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Индикатор длительности звонка
                  if (_callService.state == CallState.IN_CALL)
                    Positioned(
                      top: 24,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          '● LIVE',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
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
    );
  }
}
