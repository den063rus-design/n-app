import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'api_service.dart';

/// Вспомогательная функция для timestamp-логов.
String _ts() {
  final now = DateTime.now();
  return '${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
}

/// Состояние подключения к LiveKit комнате.
enum LiveKitConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// Инкапсулирует состояние одного звонка (LiveKit Room + треки).
///
/// Каждый экземпляр [CallSession] соответствует одному звонку.
/// В отличие от старого [LiveKitService], здесь нет глобального состояния —
/// каждый звонок имеет свой [Room], свои [ValueNotifier] и свой guard [_isConnecting].
class CallSession {
  final int callId;
  final ApiService _apiService;

  /// Максимальное количество попыток подключения (включая первую).
  /// При transient-ошибках (например, race condition с call:end на backend)
  /// повторная попытка через 1 секунду позволяет дождаться стабилизации.
  static const int maxRetries = 2;

  /// Задержка между retry-попытками.
  static const Duration retryDelay = Duration(seconds: 1);

  // LiveKit Room
  Room? _room;

  // Состояние подключения
  final ValueNotifier<LiveKitConnectionState> connectionState =
      ValueNotifier(LiveKitConnectionState.disconnected);

  /// Локальный видео-трек (для PiP preview)
  final ValueNotifier<VideoTrack?> localVideoTrack = ValueNotifier(null);

  /// Удалённый видео-трек (для fullscreen)
  final ValueNotifier<VideoTrack?> remoteVideoTrack = ValueNotifier(null);

  /// Удалённый участник (для отображения имени)
  final ValueNotifier<RemoteParticipant?> remoteParticipant =
      ValueNotifier(null);

  /// Состояние микрофона
  final ValueNotifier<bool> isMicEnabled = ValueNotifier(true);

  /// Состояние камеры
  final ValueNotifier<bool> isCameraEnabled = ValueNotifier(true);

  /// Флаг: идёт ли процесс подключения (защита от дублей)
  bool _isConnecting = false;

  /// Single in-flight connect future для идемпотентности.
  /// Если connect() уже вызван, повторный вызов возвращает этот же Future
  /// вместо того, чтобы кидать StateError.
  Future<void>? _connectFuture;

  /// Флаг: HTTP-запрос на /livekit/token отправлен, но ответ ещё не получен.
  bool isLiveKitTokenRequested = false;

  /// Cancel-функция для отписки от событий комнаты
  CancelListenFunc? _roomEventsCancel;

  CallSession({
    required this.callId,
    required ApiService apiService,
  }) : _apiService = apiService;

  /// Подключение к LiveKit комнате с retry-механизмом.
  ///
  /// 1. Запрашивает токен через ApiService.getLiveKitToken(callId)
  /// 2. Создаёт Room
  /// 3. Подключается к LiveKit
  /// 4. Включает микрофон и камеру
  ///
  /// При ошибке делает до [maxRetries] попыток с задержкой [retryDelay].
  /// Retry применяется только для transient-ошибок (token request, room connect).
  /// Guard [_connectFuture] предотвращает дублирующие вызовы:
  /// повторный вызов возвращает тот же Future вместо StateError.
  Future<void> connect() async {
    // Идемпотентность: если connect уже запущен, возвращаем существующий Future
    if (_connectFuture != null) {
      debugPrint('[CALL_SESSION] connect reused/inflight callId=$callId — returning existing future');
      return _connectFuture!;
    }

    _connectFuture = _connectWithGuard();
    try {
      await _connectFuture;
    } finally {
      _connectFuture = null;
    }
  }

  /// Внутренний метод с guard _isConnecting и try/finally.
  Future<void> _connectWithGuard() async {
    if (_isConnecting) {
      debugPrint('[CALL_SESSION] connect skipped — already connecting callId=$callId');
      return;
    }

    _isConnecting = true;

    try {
      await _connectWithRetry();
    } finally {
      _isConnecting = false;
    }
  }

  /// Внутренний метод с retry-логикой.
  Future<void> _connectWithRetry() async {
    int attempt = 0;
    while (attempt < maxRetries) {
      attempt++;
      final attemptId = attempt;

      debugPrint('[CALL_SESSION] connect attempt $attempt/$maxRetries attemptId=$attemptId callId=$callId');

      String currentStep = 'start';
      debugPrint('[CALL_SESSION_STEP] step=1 begin callId=$callId attemptId=$attemptId');

      // Stopwatch для замера времени каждого шага
      final sw = Stopwatch()..start();

      // Cleanup stale room before reconnecting
      if (_room != null) {
        debugPrint('[CALL_SESSION] cleaning up stale room before connect callId=$callId attemptId=$attemptId');
        await _cleanup();
      }
      currentStep = 'stale_check';
      debugPrint('[CALL_SESSION_STEP] step=2 stale_check roomExists=${_room != null} state=${connectionState.value} attemptId=$attemptId');

      // Если уже подключены к этому звонку — не переподключаемся
      if (_room != null &&
          _room!.connectionState == ConnectionState.connected) {
        debugPrint('[CALL_SESSION] skipped because already connected callId=$callId attemptId=$attemptId');
        return;
      }

      try {
        connectionState.value = LiveKitConnectionState.connecting;
        debugPrint('[CALL_SESSION] [${_ts()}] connectionState=connecting callId=$callId attemptId=$attemptId');
        debugPrint('[CALL_SESSION] [${_ts()}] connect begin callId=$callId attemptId=$attemptId');

        // 1. Получаем токен
        currentStep = 'token_request';
        debugPrint('[CALL_SESSION] [${_ts()}] token request start callId=$callId attemptId=$attemptId');

        isLiveKitTokenRequested = true;
        debugPrint('[CALL_SESSION] [${_ts()}] isLiveKitTokenRequested=true callId=$callId attemptId=$attemptId');

        Map<String, dynamic> tokenData;
        try {
          debugPrint('[CALL_SESSION] [${_ts()}] ⏳ before _apiService.getLiveKitToken callId=$callId attemptId=$attemptId');
          tokenData = await _apiService.getLiveKitToken(callId);
          debugPrint('[CALL_SESSION] [${_ts()}] ✅ token request success callId=$callId attemptId=$attemptId elapsedMs=${sw.elapsedMilliseconds}');
        } catch (e) {
          debugPrint('[CALL_SESSION] [${_ts()}] ❌ token request fail callId=$callId errorType=${e.runtimeType} error=$e attemptId=$attemptId elapsedMs=${sw.elapsedMilliseconds}');
          isLiveKitTokenRequested = false;
          // Если это не последняя попытка — делаем retry
          if (attempt < maxRetries) {
            debugPrint('[CALL_SESSION] [${_ts()}] retrying after token failure in ${retryDelay.inMilliseconds}ms attemptId=$attemptId');
            connectionState.value = LiveKitConnectionState.connecting;
            await Future.delayed(retryDelay);
            continue;
          }
          connectionState.value = LiveKitConnectionState.error;
          debugPrint('[CALL_SESSION] [${_ts()}] connectionState=error (token fail, no retries left) callId=$callId attemptId=$attemptId');
          rethrow;
        }

        isLiveKitTokenRequested = false;

        final token = tokenData['token'] as String;
        final wsUrl = tokenData['wsUrl'] as String;
        final roomName = tokenData['roomName'] as String? ?? 'unknown';

        debugPrint('[CALL_SESSION] [${_ts()}] token received wsUrl=$wsUrl roomName=$roomName tokenLength=${token.length} attemptId=$attemptId elapsedMs=${sw.elapsedMilliseconds}');

        // 2. Создаём Room
        currentStep = 'room_create';
        debugPrint('[CALL_SESSION] [${_ts()}] room create start attemptId=$attemptId');
        _room?.dispose();
        _room = Room(
          roomOptions: const RoomOptions(
            defaultVideoPublishOptions: VideoPublishOptions(
              simulcast: true,
            ),
          ),
        );

        // 3. Подписываемся на события комнаты
        _setupRoomListeners();

        // 4. Подключаемся
        currentStep = 'room_connect';
        debugPrint('[CALL_SESSION] [${_ts()}] ⏳ before _room!.connect wsUrl=$wsUrl roomName=$roomName attemptId=$attemptId');
        try {
          await _room!.connect(wsUrl, token);
          debugPrint('[CALL_SESSION] [${_ts()}] ✅ room connect success callId=$callId attemptId=$attemptId elapsedMs=${sw.elapsedMilliseconds}');
        } catch (e) {
          debugPrint('[CALL_SESSION] [${_ts()}] ❌ room connect fail callId=$callId errorType=${e.runtimeType} error=$e attemptId=$attemptId elapsedMs=${sw.elapsedMilliseconds}');
          if (attempt < maxRetries) {
            debugPrint('[CALL_SESSION] [${_ts()}] retrying after room connect failure in ${retryDelay.inMilliseconds}ms attemptId=$attemptId');
            connectionState.value = LiveKitConnectionState.connecting;
            await Future.delayed(retryDelay);
            continue;
          }
          connectionState.value = LiveKitConnectionState.error;
          debugPrint('[CALL_SESSION] [${_ts()}] connectionState=error (room fail, no retries left) callId=$callId attemptId=$attemptId');
          rethrow;
        }
        debugPrint('[CALL_SESSION] [${_ts()}] room connected name=${_room!.name} attemptId=$attemptId elapsedMs=${sw.elapsedMilliseconds}');

        // 5. Проверяем localParticipant
        final hasLocalParticipant = _room!.localParticipant != null;
        debugPrint('[CALL_SESSION] [${_ts()}] localParticipant exists=$hasLocalParticipant attemptId=$attemptId');

        // 6. Включаем микрофон и камеру
        if (hasLocalParticipant) {
          currentStep = 'mic_enable';
          debugPrint('[CALL_SESSION] [${_ts()}] local mic enable start attemptId=$attemptId');
          try {
            await _room!.localParticipant!.setMicrophoneEnabled(true);
            debugPrint('[CALL_SESSION] [${_ts()}] local mic enabled attemptId=$attemptId');
          } catch (e) {
            debugPrint('[CALL_SESSION] [${_ts()}] local mic enable failed error=$e attemptId=$attemptId');
          }
          currentStep = 'camera_enable';
          debugPrint('[CALL_SESSION] [${_ts()}] local camera enable start attemptId=$attemptId');
          try {
            await _room!.localParticipant!.setCameraEnabled(true);
            debugPrint('[CALL_SESSION] [${_ts()}] local camera enabled attemptId=$attemptId');
          } catch (e) {
            debugPrint('[CALL_SESSION] [${_ts()}] local camera enable failed error=$e attemptId=$attemptId');
          }
        } else {
          debugPrint('[CALL_SESSION] [${_ts()}] ⚠️ localParticipant is null after connect attemptId=$attemptId');
        }

        // 7. Обновляем состояние
        isMicEnabled.value = true;
        isCameraEnabled.value = true;

        // 8. Получаем локальный видео-трек
        currentStep = 'local_track_refresh';
        _updateLocalVideoTrack();
        debugPrint('[CALL_SESSION] [${_ts()}] ✅ after _updateLocalVideoTrack track=${localVideoTrack.value != null} attemptId=$attemptId');
        if (localVideoTrack.value != null) {
          debugPrint('[CALL_SESSION] [${_ts()}] local video track found attemptId=$attemptId');
        } else {
          debugPrint('[CALL_SESSION] [${_ts()}] local video track missing (may appear after camera warmup) attemptId=$attemptId');
        }

        connectionState.value = LiveKitConnectionState.connected;
        debugPrint('[CALL_SESSION] [${_ts()}] connectionState=connected callId=$callId attemptId=$attemptId');
        debugPrint('[CALL_SESSION] [${_ts()}] ✅ Connected successfully attemptId=$attemptId totalElapsedMs=${sw.elapsedMilliseconds}');

        sw.stop();

        // Успех — выходим из retry-цикла
        return;
      } catch (e, stack) {
        debugPrint('[CALL_SESSION_FATAL] step=$currentStep errorType=${e.runtimeType} error=$e attemptId=$attemptId elapsedMs=${sw.elapsedMilliseconds}');
        debugPrint('[CALL_SESSION_FATAL] stack=$stack');
        // Если это не последняя попытка — делаем retry
        if (attempt < maxRetries) {
          debugPrint('[CALL_SESSION] retrying after fatal error in ${retryDelay.inMilliseconds}ms attemptId=$attemptId');
          connectionState.value = LiveKitConnectionState.connecting;
          debugPrint('[CALL_SESSION] connectionState=connecting (retry after fatal) callId=$callId attemptId=$attemptId');
          await Future.delayed(retryDelay);
          continue;
        }
        connectionState.value = LiveKitConnectionState.error;
        debugPrint('[CALL_SESSION] connectionState=error (fatal, no retries left) callId=$callId attemptId=$attemptId');
        rethrow;
      }
    }
  }

  /// Отключается от LiveKit комнаты.
  Future<void> disconnect() async {
    debugPrint('[CALL_SESSION] disconnect callId=$callId');
    await _cleanup();
    debugPrint('[CALL_SESSION] ✅ disconnected callId=$callId');
  }

  /// Включить/выключить микрофон.
  Future<void> setMicrophoneEnabled(bool enabled) async {
    try {
      await _room?.localParticipant?.setMicrophoneEnabled(enabled);
      isMicEnabled.value = enabled;
      debugPrint('[CALL_SESSION] Mic ${enabled ? "enabled" : "disabled"}');
    } catch (e) {
      debugPrint('[CALL_SESSION] Mic toggle error: $e');
    }
  }

  /// Включить/выключить камеру.
  Future<void> setCameraEnabled(bool enabled) async {
    try {
      await _room?.localParticipant?.setCameraEnabled(enabled);
      isCameraEnabled.value = enabled;
      _updateLocalVideoTrack();
      debugPrint('[CALL_SESSION] Camera ${enabled ? "enabled" : "disabled"}');
    } catch (e) {
      debugPrint('[CALL_SESSION] Camera toggle error: $e');
    }
  }

  /// Переключить фронтальную/тыловую камеру.
  Future<void> switchCamera() async {
    try {
      final videoTrack = localVideoTrack.value;
      if (videoTrack != null) {
        await videoTrack.mediaStreamTrack.switchCamera();
        debugPrint('[CALL_SESSION] Camera switched');
      }
    } catch (e) {
      debugPrint('[CALL_SESSION] Camera switch error: $e');
    }
  }

  /// Настройка слушателей событий комнаты.
  void _setupRoomListeners() {
    if (_room == null) return;

    // Отменяем предыдущую подписку
    if (_roomEventsCancel != null) {
      _roomEventsCancel!.call();
      _roomEventsCancel = null;
    }

    _roomEventsCancel = _room!.events.listen((event) {
      if (event is RoomDisconnectedEvent) {
        debugPrint('[CALL_SESSION] Room disconnected');
        connectionState.value = LiveKitConnectionState.disconnected;
        localVideoTrack.value = null;
        remoteVideoTrack.value = null;
        remoteParticipant.value = null;
      } else if (event is RoomReconnectingEvent) {
        debugPrint('[CALL_SESSION] Room reconnecting...');
        connectionState.value = LiveKitConnectionState.reconnecting;
      } else if (event is RoomReconnectedEvent) {
        debugPrint('[CALL_SESSION] Room reconnected');
        connectionState.value = LiveKitConnectionState.connected;
      } else if (event is TrackPublishedEvent) {
        debugPrint(
            '[CALL_SESSION] Track published: ${event.publication.source} kind=${event.publication.kind}');
      } else if (event is TrackSubscribedEvent) {
        debugPrint(
            '[CALL_SESSION] Track subscribed: source=${event.track.source} kind=${event.track.kind} participant=${event.participant.identity}');
        _onTrackSubscribed(event.track, event.participant);
      } else if (event is TrackUnsubscribedEvent) {
        debugPrint(
            '[CALL_SESSION] Track unsubscribed: ${event.track.source}');
        if (event.track is VideoTrack) {
          remoteVideoTrack.value = null;
        }
      } else if (event is ParticipantConnectedEvent) {
        debugPrint(
            '[CALL_SESSION] remote participant connected: ${event.participant.identity}');
        remoteParticipant.value = event.participant;
      } else if (event is ParticipantDisconnectedEvent) {
        debugPrint(
            '[CALL_SESSION] remote participant disconnected: ${event.participant.identity}');
        remoteParticipant.value = null;
        remoteVideoTrack.value = null;
      }
    });
  }

  /// Обработка подписки на трек.
  void _onTrackSubscribed(Track track, RemoteParticipant participant) {
    if (track is VideoTrack) {
      debugPrint(
          '[CALL_SESSION] remote video track subscribed from ${participant.identity}');
      remoteVideoTrack.value = track;
      remoteParticipant.value = participant;
    } else if (track is AudioTrack) {
      debugPrint(
          '[CALL_SESSION] remote audio track subscribed from ${participant.identity}');
      // Audio track is handled automatically by LiveKit
    } else {
      debugPrint(
          '[CALL_SESSION] remote track subscribed (unknown type): ${track.runtimeType} from ${participant.identity}');
    }
  }

  /// Обновляет локальный видео-трек из LocalParticipant.
  void _updateLocalVideoTrack() {
    final videoPublications =
        _room?.localParticipant?.videoTrackPublications;
    if (videoPublications != null && videoPublications.isNotEmpty) {
      final firstPub = videoPublications.first;
      if (firstPub.track is VideoTrack) {
        localVideoTrack.value = firstPub.track as VideoTrack;
        return;
      }
    }
    localVideoTrack.value = null;
  }

  /// Внутренняя очистка ресурсов (без лога callId — вызывается из disconnect).
  Future<void> _cleanup() async {
    // Отменяем подписку на события
    if (_roomEventsCancel != null) {
      _roomEventsCancel!.call();
      _roomEventsCancel = null;
    }

    try {
      await _room?.disconnect();
    } catch (e) {
      debugPrint('[CALL_SESSION] Disconnect error: $e');
    }

    _room?.dispose();
    _room = null;

    localVideoTrack.value = null;
    remoteVideoTrack.value = null;
    remoteParticipant.value = null;
    connectionState.value = LiveKitConnectionState.disconnected;
  }

  /// Освобождение ресурсов.
  void dispose() {
    debugPrint('[CALL_SESSION] dispose callId=$callId');
    if (_roomEventsCancel != null) {
      _roomEventsCancel!.call();
      _roomEventsCancel = null;
    }
    _room?.dispose();
    _room = null;
    connectionState.dispose();
    localVideoTrack.dispose();
    remoteVideoTrack.dispose();
    remoteParticipant.dispose();
    isMicEnabled.dispose();
    isCameraEnabled.dispose();
  }
}