import 'dart:async';
import 'package:flutter/material.dart';
import '../services/call_service.dart';
import '../services/call_logger.dart';
import '../services/call_ringtone_service.dart';

class IncomingCallDialog extends StatefulWidget {
  final int callerId;
  final String callerName;
  final int callId;

  const IncomingCallDialog({
    super.key,
    required this.callerId,
    required this.callerName,
    required this.callId,
  });

  @override
  State<IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<IncomingCallDialog>
    with SingleTickerProviderStateMixin {
  final CallService _callService = CallService();
  final CallLogger _callLogger = CallLogger();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isHandled = false;
  StreamSubscription<CallState>? _stateSubscription;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    final currentState = _callService.state;
    if (currentState == CallState.ENDED || currentState == CallState.IDLE) {
      _isHandled = true;
      _callService.markIncomingDialogClosed();
      CallRingtoneService().stopAllCallSounds();
      Future.microtask(() {
        if (mounted) {
          Navigator.of(context).pop(false);
        }
      });
      return;
    }

    _callService.markIncomingDialogOpen();
    CallRingtoneService().playIncomingRingtone();

    _stateSubscription = _callService.stateStream.listen((state) {
      if (_isHandled) return;
      if (state == CallState.ENDED || state == CallState.IDLE) {
        _log('remote end detected (state=$state), auto-closing');
        _onReject();
      }
    });

    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _log('dispose handled=$_isHandled');
    _stateSubscription?.cancel();
    if (!_isHandled) {
      CallRingtoneService().stopAllCallSounds();
      _callService.markIncomingDialogClosed();
    }
    _pulseController.dispose();
    super.dispose();
  }

  void _log(String message) {
    print('[INCOMING_DIALOG] $message');
    _callLogger.log('IncomingCallDialog', message);
  }

  void _onAccept() {
    if (_isHandled) return;
    _isHandled = true;
    _log('accept pressed');
    CallRingtoneService().stopAllCallSounds();
    if (mounted) Navigator.of(context).pop(true);
  }

  void _onReject() {
    if (_isHandled) return;
    _isHandled = true;
    _log('reject pressed');
    CallRingtoneService().stopAllCallSounds();
    _callService.markIncomingDialogClosed();
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        _log('onPopInvokedWithResult didPop=$didPop result=$result');
        if (!didPop && !_isHandled) {
          _onReject();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: 0.85),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.1),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 50,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.callerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Входящий звонок...',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 60),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        FloatingActionButton(
                          onPressed: _onReject,
                          backgroundColor: Colors.red,
                          heroTag: 'reject',
                          child: const Icon(
                            Icons.call_end,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Отклонить',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _pulseAnimation.value,
                              child: FloatingActionButton(
                                onPressed: _onAccept,
                                backgroundColor: Colors.green,
                                heroTag: 'accept',
                                child: const Icon(
                                  Icons.call,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Принять',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
