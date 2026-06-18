import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'api_service.dart';

/// Состояние подключения к LiveKit комнате.
enum LiveKitConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// Singleton-сервис для управления подключением к LiveKit.
///
/// Отвечает за:
/// - получение токена через ApiService
/// - создание и управление Room
/// - подключение/отключение от LiveKit
/// - управление микрофоном и камерой
/// - предоставление видео-треков в UI
class LiveKitService {
  static final LiveKitService _instance = LiveKitService._internal();
  factory LiveKitService() => _instance;
  LiveKitService._internal();

  final ApiService _apiService = ApiService();

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

  /// Текущий callId (для логирования)
  int? _currentCallId;

  /// Флаг: идёт ли процесс подключения (защита от дублей)
  bool _isConnecting = false;

  /// Cancel-функция для отписки от событий комнаты
  CancelListenFunc? _roomEventsCancel;

  /// Подключение к LiveKit комнате для указанного звонка.
  ///
  /// 1. Запрашивает токен через ApiService.getLiveKitToken(callId)
  /// 2. Создаёт Room
  /// 3. Подключается к LiveKit
  /// 4. Включает микрофон и камеру
  Future<void> connectToCall(int callId) async {
    if (_isConnecting) {
      debugPrint('[LIVEKIT] 🔴 LIVEKIT connectToCall skipped — already connecting callId=$callId');
      throw StateError('LiveKit connection already in progress for callId=$callId');
    }

    String currentStep = 'start';
    debugPrint('[LIVEKIT_STEP] step=1 begin callId=$callId');

    // Cleanup stale room before reconnecting
    if (_room != null) {
      debugPrint('[LIVEKIT] LIVEKIT cleaning up stale room before connect callId=$callId');
      await disconnect();
    }
    currentStep = 'stale_check';
    debugPrint('[LIVEKIT_STEP] step=2 stale_check roomExists=${_room != null} currentCallId=$_currentCallId state=${connectionState.value}');

    // Если уже подключены к этому звонку — не переподключаемся
    if (_room != null &&
        _currentCallId == callId &&
        _room!.connectionState == ConnectionState.connected) {
      debugPrint('[LIVEKIT] LIVEKIT skipped because already connected to same call callId=$callId');
      return;
    }

    _isConnecting = true;
    _currentCallId = callId;

    try {
      connectionState.value = LiveKitConnectionState.connecting;
      debugPrint('[LIVEKIT] LIVEKIT connectToCall begin callId=$callId');

      // 1. Получаем токен
      currentStep = 'token_request';
      debugPrint('[LIVEKIT_STEP] step=3 token_request_start callId=$callId');
      debugPrint('[LIVEKIT] LIVEKIT token request start callId=$callId');
      Map<String, dynamic> tokenData;
      try {
        tokenData = await _apiService.getLiveKitToken(callId);
      } catch (e) {
        debugPrint('[LIVEKIT] LIVEKIT token request failed error=$e');
        connectionState.value = LiveKitConnectionState.error;
        rethrow;
      }
      final token = tokenData['token'] as String;
      final wsUrl = tokenData['wsUrl'] as String;
      final roomName = tokenData['roomName'] as String? ?? 'unknown';

      debugPrint('[LIVEKIT_STEP] step=4 token_received wsUrl=$wsUrl roomName=$roomName tokenLength=${token.length}');
      debugPrint('[LIVEKIT] LIVEKIT token received wsUrl=$wsUrl roomName=$roomName');

      // 2. Создаём Room
      currentStep = 'room_create';
      debugPrint('[LIVEKIT_STEP] step=5 room_create_start');
      debugPrint('[LIVEKIT] LIVEKIT room create start');
      _room?.dispose();
      _room = Room(
        roomOptions: const RoomOptions(
          defaultVideoPublishOptions: VideoPublishOptions(
            simulcast: true,
          ),
        ),
      );
      debugPrint('[LIVEKIT_STEP] step=6 room_created roomNull=${_room == null}');

      // 3. Подписываемся на события комнаты
      _setupRoomListeners();

      // 4. Подключаемся
      currentStep = 'room_connect';
      debugPrint('[LIVEKIT_STEP] step=7 room_connect_start wsUrl=$wsUrl roomName=$roomName');
      debugPrint('[LIVEKIT] LIVEKIT room connect start wsUrl=$wsUrl roomName=$roomName');
      try {
        await _room!.connect(wsUrl, token);
      } catch (e) {
        debugPrint('[LIVEKIT] LIVEKIT room connect failed error=$e');
        connectionState.value = LiveKitConnectionState.error;
        rethrow;
      }
      debugPrint('[LIVEKIT_STEP] step=8 room_connected actualRoomName=${_room?.name}');
      debugPrint('[LIVEKIT] LIVEKIT room connected name=${_room!.name}');

      // 5. Проверяем localParticipant
      final hasLocalParticipant = _room!.localParticipant != null;
      debugPrint('[LIVEKIT_STEP] step=9 local_participant_exists=${_room?.localParticipant != null}');
      debugPrint('[LIVEKIT] LIVEKIT localParticipant exists=$hasLocalParticipant');

      // 6. Включаем микрофон и камеру
      if (hasLocalParticipant) {
        currentStep = 'mic_enable';
        debugPrint('[LIVEKIT] LIVEKIT local mic enable start');
        try {
          await _room!.localParticipant!.setMicrophoneEnabled(true);
          debugPrint('[LIVEKIT] LIVEKIT local mic enable done');
        } catch (e) {
          debugPrint('[LIVEKIT] LIVEKIT local mic enable failed error=$e');
        }
        currentStep = 'camera_enable';
        debugPrint('[LIVEKIT_STEP] step=10 camera_enable_start');
        debugPrint('[LIVEKIT] LIVEKIT local camera enable start');
        try {
          await _room!.localParticipant!.setCameraEnabled(true);
          debugPrint('[LIVEKIT] LIVEKIT local camera enable done');
        } catch (e) {
          debugPrint('[LIVEKIT] LIVEKIT local camera enable failed error=$e');
        }
      } else {
        debugPrint('[LIVEKIT] ⚠️ LIVEKIT localParticipant is null after connect');
      }

      // 7. Обновляем состояние
      isMicEnabled.value = true;
      isCameraEnabled.value = true;

      // 8. Получаем локальный видео-трек
      currentStep = 'local_track_refresh';
      _updateLocalVideoTrack();
      debugPrint('[LIVEKIT_STEP] step=11 local_track_present=${localVideoTrack.value != null}');
      if (localVideoTrack.value != null) {
        debugPrint('[LIVEKIT] LIVEKIT local video track found');
      } else {
        debugPrint('[LIVEKIT] LIVEKIT local video track missing (may appear after camera warmup)');
      }

      connectionState.value = LiveKitConnectionState.connected;
      debugPrint('[LIVEKIT_STEP] step=12 success connectionState=${connectionState.value}');
      debugPrint('[LIVEKIT] LIVEKIT ✅ Connected successfully');
    } catch (e, stack) {
      debugPrint('[LIVEKIT_FATAL] step=$currentStep error=$e');
      debugPrint('[LIVEKIT_FATAL] stack=$stack');
      connectionState.value = LiveKitConnectionState.error;
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  /// Отключается от LiveKit комнаты.
  Future<void> disconnect() async {
    debugPrint('[LIVEKIT] LIVEKIT disconnect callId=$_currentCallId');

    // Отменяем подписку на события
    if (_roomEventsCancel != null) {
      _roomEventsCancel!.call();
      _roomEventsCancel = null;
    }

    try {
      await _room?.disconnect();
    } catch (e) {
      debugPrint('[LIVEKIT] Disconnect error: $e');
    }

    _room?.dispose();
    _room = null;

    localVideoTrack.value = null;
    remoteVideoTrack.value = null;
    remoteParticipant.value = null;
    connectionState.value = LiveKitConnectionState.disconnected;
    _currentCallId = null;

    debugPrint('[LIVEKIT] ✅ LIVEKIT disconnected');
  }

  /// Включить/выключить микрофон.
  Future<void> setMicrophoneEnabled(bool enabled) async {
    try {
      await _room?.localParticipant?.setMicrophoneEnabled(enabled);
      isMicEnabled.value = enabled;
      debugPrint('[LIVEKIT] Mic ${enabled ? "enabled" : "disabled"}');
    } catch (e) {
      debugPrint('[LIVEKIT] Mic toggle error: $e');
    }
  }

  /// Включить/выключить камеру.
  Future<void> setCameraEnabled(bool enabled) async {
    try {
      await _room?.localParticipant?.setCameraEnabled(enabled);
      isCameraEnabled.value = enabled;
      _updateLocalVideoTrack();
      debugPrint('[LIVEKIT] Camera ${enabled ? "enabled" : "disabled"}');
    } catch (e) {
      debugPrint('[LIVEKIT] Camera toggle error: $e');
    }
  }

  /// Переключить фронтальную/тыловую камеру.
  Future<void> switchCamera() async {
    try {
      final videoTrack = localVideoTrack.value;
      if (videoTrack != null) {
        await videoTrack.mediaStreamTrack.switchCamera();
        debugPrint('[LIVEKIT] Camera switched');
      }
    } catch (e) {
      debugPrint('[LIVEKIT] Camera switch error: $e');
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

    // Используем events.listen() который возвращает CancelListenFunc
    _roomEventsCancel = _room!.events.listen((event) {
      if (event is RoomDisconnectedEvent) {
        debugPrint('[LIVEKIT] LIVEKIT Room disconnected');
        connectionState.value = LiveKitConnectionState.disconnected;
        localVideoTrack.value = null;
        remoteVideoTrack.value = null;
        remoteParticipant.value = null;
      } else if (event is RoomReconnectingEvent) {
        debugPrint('[LIVEKIT] LIVEKIT Room reconnecting...');
        connectionState.value = LiveKitConnectionState.reconnecting;
      } else if (event is RoomReconnectedEvent) {
        debugPrint('[LIVEKIT] LIVEKIT Room reconnected');
        connectionState.value = LiveKitConnectionState.connected;
      } else if (event is TrackPublishedEvent) {
        debugPrint(
            '[LIVEKIT] LIVEKIT Track published: ${event.publication.source} kind=${event.publication.kind}');
      } else if (event is TrackSubscribedEvent) {
        debugPrint(
            '[LIVEKIT] LIVEKIT Track subscribed: source=${event.track.source} kind=${event.track.kind} participant=${event.participant.identity}');
        _onTrackSubscribed(event.track, event.participant);
      } else if (event is TrackUnsubscribedEvent) {
        debugPrint(
            '[LIVEKIT] LIVEKIT Track unsubscribed: ${event.track.source}');
        if (event.track is VideoTrack) {
          remoteVideoTrack.value = null;
        }
      } else if (event is ParticipantConnectedEvent) {
        debugPrint(
            '[LIVEKIT] LIVEKIT remote participant connected: ${event.participant.identity}');
        remoteParticipant.value = event.participant;
      } else if (event is ParticipantDisconnectedEvent) {
        debugPrint(
            '[LIVEKIT] LIVEKIT remote participant disconnected: ${event.participant.identity}');
        remoteParticipant.value = null;
        remoteVideoTrack.value = null;
      }
    });
  }

  /// Обработка подписки на трек.
  void _onTrackSubscribed(Track track, RemoteParticipant participant) {
    if (track is VideoTrack) {
      debugPrint(
          '[LIVEKIT] LIVEKIT remote video track subscribed from ${participant.identity}');
      remoteVideoTrack.value = track;
      remoteParticipant.value = participant;
    } else if (track is AudioTrack) {
      debugPrint(
          '[LIVEKIT] LIVEKIT remote audio track subscribed from ${participant.identity}');
      // Audio track is handled automatically by LiveKit
    } else {
      debugPrint(
          '[LIVEKIT] LIVEKIT remote track subscribed (unknown type): ${track.runtimeType} from ${participant.identity}');
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

  /// Освобождение ресурсов.
  void dispose() {
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