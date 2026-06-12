import 'dart:async';
import 'package:flutter/material.dart';
import '../services/call_service.dart';
import '../services/call_logger.dart';
import '../services/call_ringtone_service.dart';

/// Модальное окно входящего звонка.
///
/// Показывается при получении входящего звонка (call:incoming).
/// Содержит:
/// - имя звонящего
/// - зелёная кнопка "Принять"
/// - красная кнопка "Отклонить"
///
/// Возвращает bool через Navigator.pop:
/// - true — принято
/// - false — отклонено
///
/// ВАЖНО: Диалог НЕ вызывает acceptCall/rejectCall сам.
/// Он только возвращает результат. Вызов acceptCall/rejectCall
/// делает тот, кто открыл диалог (app.dart).
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

  /// Guard от двойного вызова accept/reject.
  bool _isHandled = false;

  /// Подписка на stateStream для автозакрытия при удалённом завершении звонка.
  StreamSubscription<CallState>? _stateSubscription;

  @override
  void initState() {
    super.initState();

    // Проверяем текущее состояние: если звонок уже завершён — закрываемся без анимации
    final currentState = _callService.state;
    if (currentState == CallState.ENDED || currentState == CallState.IDLE) {
      _isHandled = true;
      _callService.markIncomingDialogClosed();
      CallRingtoneService().stopAllCallSounds();
      // Не вызываем super.dispose() — initState только начался, dispose вызовется позже.
      // Просто помечаем handled и не стартуем анимацию/звук.
      _pulseController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      );
      _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
      );
      // Сразу закрываем диалог через микротаск, чтобы build() успел вернуть виджет
      Future.microtask(() {
        if (mounted && !_isHandled) return; // дополнительная проверка
        if (mounted) Navigator.of(context).pop(false);
      });
      return;
    }

    _callService.markIncomingDialogOpen();
    CallRingtoneService().playIncomingRingtone();

    // Подписываемся на stateStream для автозакрытия при удалённом завершении звонка
    _stateSubscription = _callService.stateStream.listen((state) {
      if (_isHandled) return;
      if (state == CallState.ENDED || state == CallState.IDLE) {
        _log('📞 remote end detected (state=$state), auto-closing');
        _onReject();
      }
    });

    // Анимация пульсации для кнопки "Принять"
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    // Если _isHandled уже true — _onReject уже вызвал cleanup, не дублируем
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
    _log('✅ accept');
    CallRingtoneService().stopAllCallSounds();
    if (mounted) Navigator.of(context).pop(true);
  }

  void _onReject() {
    if (_isHandled) return;
    _isHandled = true;
    _log('❌ reject');
    CallRingtoneService().stopAllCallSounds();
    _callService.markIncomingDialogClosed();
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // Системный Back заблокирован (canPop: false).
        // Если didPop == false — пользователь нажал Back,
        // обрабатываем как reject (только если ещё не обработано).
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
                // Аватар звонящего
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
                // Имя звонящего
                Text(
                  widget.callerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                // Статус
                const Text(
                  'Входящий звонок...',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 60),
                // Кнопки
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Отклонить
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
                    // Принять (с пульсацией)
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