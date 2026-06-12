import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'call_logger.dart';

/// Сервис для воспроизведения звуков звонков.
///
/// Поддерживает два независимых звуковых потока:
/// - Входящий рингтон (для принимающего звонок)
/// - Исходящий гудок (для звонящего)
///
/// Использует пакет audioplayers.
/// Предотвращает дублирование звука (защита от повторного play, если уже играет).
///
/// Если asset-файл не найден — просто логирует ошибку,
/// без фальшивых fallback-попыток.
class CallRingtoneService {
  static final CallRingtoneService _instance = CallRingtoneService._internal();
  factory CallRingtoneService() => _instance;
  CallRingtoneService._internal() {
    _player = AudioPlayer(playerId: 'incoming_ringtone');
    _outgoingPlayer = AudioPlayer(playerId: 'outgoing_ringback');
  }

  late final AudioPlayer _player;
  late final AudioPlayer _outgoingPlayer;

  final CallLogger _callLogger = CallLogger();

  final AudioContext _audioContext = AudioContext(
    android: AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.notification,
      audioFocus: AndroidAudioFocus.gain,
    ),
  );

  bool _isIncomingPlaying = false;
  bool _isOutgoingPlaying = false;

  // --- Incoming ringtone (для принимающего) ---

  /// Воспроизводит рингтон входящего звонка.
  ///
  /// Если рингтон уже играет — не дублирует.
  /// Использует asset-файл 'assets/ringtone.mp3'.
  /// Если файл не найден — логирует ошибку.
  Future<void> playIncomingRingtone() async {
    if (_isIncomingPlaying) {
      _log('⚠️ playIncomingRingtone — already playing, skipping');
      return;
    }

    _log('🔔 playIncomingRingtone — starting');
    _isIncomingPlaying = true;

    try {
      _log('🔔 playIncomingRingtone — setReleaseMode done');
      await _player.setReleaseMode(ReleaseMode.loop);
      _log('🔔 playIncomingRingtone — setVolume done');
      await _player.setVolume(1.0);
      _log('🔔 playIncomingRingtone — setAudioContext done');
      await _player.setAudioContext(_audioContext);
      _log('🔔 playIncomingRingtone — play called');
      await _player.play(AssetSource('ringtone.mp3'));
      _log('✅ playIncomingRingtone — playing from assets/ringtone.mp3');
    } catch (e) {
      _log('❌ playIncomingRingtone — asset not found or playback failed: $e');
      _log('❌ playIncomingRingtone — ringtone will NOT play. Place a real ringtone.mp3 in frontend/assets/');
      _isIncomingPlaying = false;
    }
  }

  /// Останавливает рингтон входящего звонка.
  Future<void> stopIncomingRingtone() async {
    if (!_isIncomingPlaying) {
      _log('⚠️ stopIncomingRingtone — not playing, skipping');
      return;
    }

    _log('🔇 stopIncomingRingtone — stopping ringtone');
    _isIncomingPlaying = false;
    try {
      await _player.stop();
      _log('✅ stopIncomingRingtone — stopped');
    } catch (e) {
      _log('❌ stopIncomingRingtone — error: $e');
    }
  }

  // --- Outgoing ringback tone (для звонящего) ---

  /// Воспроизводит исходящий гудок (ringback tone).
  ///
  /// Если гудок уже играет — не дублирует.
  /// Использует asset-файл 'assets/outgoing_ringback.wav'.
  /// Если файл не найден — логирует ошибку.
  Future<void> playOutgoingRingbackTone() async {
    if (_isOutgoingPlaying) {
      _log('⚠️ playOutgoingRingbackTone — already playing, skipping');
      return;
    }

    _log('📞 playOutgoingRingbackTone — starting');
    _isOutgoingPlaying = true;

    try {
      _log('📞 playOutgoingRingbackTone — setReleaseMode done');
      await _outgoingPlayer.setReleaseMode(ReleaseMode.loop);
      _log('📞 playOutgoingRingbackTone — setVolume done');
      await _outgoingPlayer.setVolume(1.0);
      _log('📞 playOutgoingRingbackTone — setAudioContext done');
      await _outgoingPlayer.setAudioContext(_audioContext);
      _log('📞 playOutgoingRingbackTone — play called');
      await _outgoingPlayer.play(AssetSource('outgoing_ringback.wav'));
      _log('✅ playOutgoingRingbackTone — playing from assets/outgoing_ringback.wav');
    } catch (e) {
      _log('❌ playOutgoingRingbackTone — asset not found or playback failed: $e');
      _log('❌ playOutgoingRingbackTone — ringback will NOT play. Place a real outgoing_ringback.wav in frontend/assets/');
      _isOutgoingPlaying = false;
    }
  }

  /// Останавливает исходящий гудок (ringback tone).
  Future<void> stopOutgoingRingbackTone() async {
    if (!_isOutgoingPlaying) {
      _log('⚠️ stopOutgoingRingbackTone — not playing, skipping');
      return;
    }

    _log('🔇 stopOutgoingRingbackTone — stopping ringback tone');
    _isOutgoingPlaying = false;
    try {
      await _outgoingPlayer.stop();
      _log('✅ stopOutgoingRingbackTone — stopped');
    } catch (e) {
      _log('❌ stopOutgoingRingbackTone — error: $e');
    }
  }

  // --- Stop all ---

  /// Останавливает ЛЮБОЙ call-related звук (входящий рингтон + исходящий гудок).
  Future<void> stopAllCallSounds() async {
    _log('🛑 stopAllCallSounds — stopping all call sounds');
    await stopIncomingRingtone();
    await stopOutgoingRingbackTone();
    _log('✅ stopAllCallSounds — all sounds stopped');
  }

  /// Проверяет, играет ли входящий рингтон.
  bool get isIncomingPlaying => _isIncomingPlaying;

  /// Проверяет, играет ли исходящий гудок.
  bool get isOutgoingPlaying => _isOutgoingPlaying;

  void _log(String message) {
    debugPrint('[RINGTONE_SERVICE] $message');
    _callLogger.log('CallRingtoneService', message);
  }

  /// Полное освобождение ресурсов (при уничтожении приложения).
  Future<void> dispose() async {
    _log('🧹 dispose — releasing resources');
    await stopAllCallSounds();
    await _player.dispose();
    await _outgoingPlayer.dispose();
    _log('✅ dispose — done');
  }
}
