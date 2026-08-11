import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'call_logger.dart';

/// РЎРµСЂРІРёСЃ РґР»СЏ РІРѕСЃРїСЂРѕРёР·РІРµРґРµРЅРёСЏ Р·РІСѓРєРѕРІ Р·РІРѕРЅРєРѕРІ.
///
/// РџРѕРґРґРµСЂР¶РёРІР°РµС‚ РґРІР° РЅРµР·Р°РІРёСЃРёРјС‹С… Р·РІСѓРєРѕРІС‹С… РїРѕС‚РѕРєР°:
/// - Р’С…РѕРґСЏС‰РёР№ СЂРёРЅРіС‚РѕРЅ (РґР»СЏ РїСЂРёРЅРёРјР°СЋС‰РµРіРѕ Р·РІРѕРЅРѕРє)
/// - РСЃС…РѕРґСЏС‰РёР№ РіСѓРґРѕРє (РґР»СЏ Р·РІРѕРЅСЏС‰РµРіРѕ)
///
/// РСЃРїРѕР»СЊР·СѓРµС‚ РїР°РєРµС‚ audioplayers.
/// РџСЂРµРґРѕС‚РІСЂР°С‰Р°РµС‚ РґСѓР±Р»РёСЂРѕРІР°РЅРёРµ Р·РІСѓРєР° (Р·Р°С‰РёС‚Р° РѕС‚ РїРѕРІС‚РѕСЂРЅРѕРіРѕ play, РµСЃР»Рё СѓР¶Рµ РёРіСЂР°РµС‚).
///
/// Р•СЃР»Рё asset-С„Р°Р№Р» РЅРµ РЅР°Р№РґРµРЅ вЂ” РїСЂРѕСЃС‚Рѕ Р»РѕРіРёСЂСѓРµС‚ РѕС€РёР±РєСѓ,
/// Р±РµР· С„Р°Р»СЊС€РёРІС‹С… fallback-РїРѕРїС‹С‚РѕРє.
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

  Future<void> _safePlayerOp(
    String label,
    Future<void> Function() operation,
  ) async {
    try {
      await operation().timeout(const Duration(seconds: 3));
    } on TimeoutException {
      _log('⚠️ $label — timeout, skipping');
    } catch (e) {
      _log('❌ $label — error: $e');
      rethrow;
    }
  }

  // --- Incoming ringtone (РґР»СЏ РїСЂРёРЅРёРјР°СЋС‰РµРіРѕ) ---

  /// Р’РѕСЃРїСЂРѕРёР·РІРѕРґРёС‚ СЂРёРЅРіС‚РѕРЅ РІС…РѕРґСЏС‰РµРіРѕ Р·РІРѕРЅРєР°.
  ///
  /// Р•СЃР»Рё СЂРёРЅРіС‚РѕРЅ СѓР¶Рµ РёРіСЂР°РµС‚ вЂ” РЅРµ РґСѓР±Р»РёСЂСѓРµС‚.
  /// РСЃРїРѕР»СЊР·СѓРµС‚ asset-С„Р°Р№Р» 'assets/ringtone.mp3'.
  /// Р•СЃР»Рё С„Р°Р№Р» РЅРµ РЅР°Р№РґРµРЅ вЂ” Р»РѕРіРёСЂСѓРµС‚ РѕС€РёР±РєСѓ.
  Future<void> playIncomingRingtone() async {
    if (_isIncomingPlaying) {
      _log('вљ пёЏ playIncomingRingtone вЂ” already playing, skipping');
      return;
    }

    _log('рџ”” playIncomingRingtone вЂ” starting');
    _isIncomingPlaying = true;

    try {
      _log('рџ”” playIncomingRingtone вЂ” setReleaseMode done');
      await _safePlayerOp('playIncomingRingtone setReleaseMode', () => _player.setReleaseMode(ReleaseMode.loop));
      _log('рџ”” playIncomingRingtone вЂ” setVolume done');
      await _safePlayerOp('playIncomingRingtone setVolume', () => _player.setVolume(1.0));
      _log('рџ”” playIncomingRingtone вЂ” setAudioContext done');
      await _safePlayerOp('playIncomingRingtone setAudioContext', () => _player.setAudioContext(_audioContext));
      _log('рџ”” playIncomingRingtone вЂ” play called');
      await _safePlayerOp('playIncomingRingtone play', () => _player.play(AssetSource('ringtone.mp3')));
      _log('вњ… playIncomingRingtone вЂ” playing from assets/ringtone.mp3');
    } catch (e) {
      _log('вќЊ playIncomingRingtone вЂ” asset not found or playback failed: $e');
      _log('вќЊ playIncomingRingtone вЂ” ringtone will NOT play. Place a real ringtone.mp3 in frontend/assets/');
      _isIncomingPlaying = false;
    }
  }

  /// РћСЃС‚Р°РЅР°РІР»РёРІР°РµС‚ СЂРёРЅРіС‚РѕРЅ РІС…РѕРґСЏС‰РµРіРѕ Р·РІРѕРЅРєР°.
  Future<void> stopIncomingRingtone() async {
    if (!_isIncomingPlaying) {
      _log('вљ пёЏ stopIncomingRingtone вЂ” not playing, skipping');
      return;
    }

    _log('рџ”‡ stopIncomingRingtone вЂ” stopping ringtone');
    _isIncomingPlaying = false;
    try {
      await _safePlayerOp('stopIncomingRingtone stop', () => _player.stop());
      _log('вњ… stopIncomingRingtone вЂ” stopped');
    } catch (e) {
      _log('вќЊ stopIncomingRingtone вЂ” error: $e');
    }
  }

  // --- Outgoing ringback tone (РґР»СЏ Р·РІРѕРЅСЏС‰РµРіРѕ) ---

  /// Р’РѕСЃРїСЂРѕРёР·РІРѕРґРёС‚ РёСЃС…РѕРґСЏС‰РёР№ РіСѓРґРѕРє (ringback tone).
  ///
  /// Р•СЃР»Рё РіСѓРґРѕРє СѓР¶Рµ РёРіСЂР°РµС‚ вЂ” РЅРµ РґСѓР±Р»РёСЂСѓРµС‚.
  /// РСЃРїРѕР»СЊР·СѓРµС‚ asset-С„Р°Р№Р» 'assets/outgoing_ringback.wav'.
  /// Р•СЃР»Рё С„Р°Р№Р» РЅРµ РЅР°Р№РґРµРЅ вЂ” Р»РѕРіРёСЂСѓРµС‚ РѕС€РёР±РєСѓ.
  Future<void> playOutgoingRingbackTone() async {
    if (_isOutgoingPlaying) {
      _log('вљ пёЏ playOutgoingRingbackTone вЂ” already playing, skipping');
      return;
    }

    _log('рџ“ћ playOutgoingRingbackTone вЂ” starting');
    _isOutgoingPlaying = true;

    try {
      _log('рџ“ћ playOutgoingRingbackTone вЂ” setReleaseMode done');
      await _safePlayerOp('playOutgoingRingbackTone setReleaseMode', () => _outgoingPlayer.setReleaseMode(ReleaseMode.loop));
      _log('рџ“ћ playOutgoingRingbackTone вЂ” setVolume done');
      await _safePlayerOp('playOutgoingRingbackTone setVolume', () => _outgoingPlayer.setVolume(1.0));
      _log('рџ“ћ playOutgoingRingbackTone вЂ” setAudioContext done');
      await _safePlayerOp('playOutgoingRingbackTone setAudioContext', () => _outgoingPlayer.setAudioContext(_audioContext));
      _log('рџ“ћ playOutgoingRingbackTone вЂ” play called');
      await _safePlayerOp('playOutgoingRingbackTone play', () => _outgoingPlayer.play(AssetSource('outgoing_ringback.wav')));
      _log('вњ… playOutgoingRingbackTone вЂ” playing from assets/outgoing_ringback.wav');
    } catch (e) {
      _log('вќЊ playOutgoingRingbackTone вЂ” asset not found or playback failed: $e');
      _log('вќЊ playOutgoingRingbackTone вЂ” ringback will NOT play. Place a real outgoing_ringback.wav in frontend/assets/');
      _isOutgoingPlaying = false;
    }
  }

  /// РћСЃС‚Р°РЅР°РІР»РёРІР°РµС‚ РёСЃС…РѕРґСЏС‰РёР№ РіСѓРґРѕРє (ringback tone).
  Future<void> stopOutgoingRingbackTone() async {
    if (!_isOutgoingPlaying) {
      _log('вљ пёЏ stopOutgoingRingbackTone вЂ” not playing, skipping');
      return;
    }

    _log('рџ”‡ stopOutgoingRingbackTone вЂ” stopping ringback tone');
    _isOutgoingPlaying = false;
    try {
      await _safePlayerOp('stopOutgoingRingbackTone stop', () => _outgoingPlayer.stop());
      _log('вњ… stopOutgoingRingbackTone вЂ” stopped');
    } catch (e) {
      _log('вќЊ stopOutgoingRingbackTone вЂ” error: $e');
    }
  }

  // --- Stop all ---

  /// РћСЃС‚Р°РЅР°РІР»РёРІР°РµС‚ Р›Р®Р‘РћР™ call-related Р·РІСѓРє (РІС…РѕРґСЏС‰РёР№ СЂРёРЅРіС‚РѕРЅ + РёСЃС…РѕРґСЏС‰РёР№ РіСѓРґРѕРє).
  Future<void> stopAllCallSounds() async {
    _log('рџ›‘ stopAllCallSounds вЂ” stopping all call sounds');
    await stopIncomingRingtone();
    await stopOutgoingRingbackTone();
    _log('вњ… stopAllCallSounds вЂ” all sounds stopped');
  }

  /// РџСЂРѕРІРµСЂСЏРµС‚, РёРіСЂР°РµС‚ Р»Рё РІС…РѕРґСЏС‰РёР№ СЂРёРЅРіС‚РѕРЅ.
  bool get isIncomingPlaying => _isIncomingPlaying;

  /// РџСЂРѕРІРµСЂСЏРµС‚, РёРіСЂР°РµС‚ Р»Рё РёСЃС…РѕРґСЏС‰РёР№ РіСѓРґРѕРє.
  bool get isOutgoingPlaying => _isOutgoingPlaying;

  void _log(String message) {
    debugPrint('[RINGTONE_SERVICE] $message');
    _callLogger.log('CallRingtoneService', message);
  }

  /// РџРѕР»РЅРѕРµ РѕСЃРІРѕР±РѕР¶РґРµРЅРёРµ СЂРµСЃСѓСЂСЃРѕРІ (РїСЂРё СѓРЅРёС‡С‚РѕР¶РµРЅРёРё РїСЂРёР»РѕР¶РµРЅРёСЏ).
  Future<void> dispose() async {
    _log('рџ§№ dispose вЂ” releasing resources');
    await stopAllCallSounds();
    await _player.dispose();
    await _outgoingPlayer.dispose();
    _log('вњ… dispose вЂ” done');
  }
}
