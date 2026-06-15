import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../services/call_service.dart';
import '../services/call_logger.dart';
import '../services/livekit_service.dart';

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
  final LiveKitService _liveKitService = LiveKitService();

  StreamSubscription<CallState>? _stateSub;
  StreamSubscription<bool>? _minimizedSub;

  Offset _position = const Offset(16, 100);
  bool _visible = false;

  // Подписки на LiveKit
  VoidCallback? _remoteVideoListener;

  bool _shouldShowOverlay(CallState state, bool isMinimized) {
    if (state == CallState.ENDED || state == CallState.IDLE) return false;
    return isMinimized &&
        (state == CallState.CALLING ||
            state == CallState.RINGING ||
            state == CallState.IN_CALL);
  }

  void _updateVisibility(CallState state, bool isMinimized) {
    final shouldShow = _shouldShowOverlay(state, isMinimized);
    if (shouldShow != _visible) {
      setState(() {
        _visible = shouldShow;
      });
      if (shouldShow) {
        _log('overlay shown');
      } else {
        _log('overlay hidden');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _subscribe();

    // Подписываемся на remote video
    _remoteVideoListener = () {
      if (mounted) setState(() {});
    };
    _liveKitService.remoteVideoTrack.addListener(_remoteVideoListener!);
  }

  void _subscribe() {
    _stateSub = _callService.stateStream.listen((state) {
      if (!mounted) return;
      _updateVisibility(state, _callService.isMinimized);
    });

    _minimizedSub = _callService.minimizedStream.listen((isMinimized) {
      if (!mounted) return;
      _updateVisibility(_callService.state, isMinimized);
    });

    _visible = _shouldShowOverlay(_callService.state, _callService.isMinimized);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _minimizedSub?.cancel();
    if (_remoteVideoListener != null) {
      _liveKitService.remoteVideoTrack.removeListener(_remoteVideoListener!);
    }
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
                  // Remote video через LiveKit
                  if (_liveKitService.remoteVideoTrack.value != null)
                    VideoTrackRenderer(
                      _liveKitService.remoteVideoTrack.value!,
                      fit: VideoViewFit.cover,
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