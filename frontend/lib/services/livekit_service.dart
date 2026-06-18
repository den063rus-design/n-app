import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'call_session.dart';

/// Состояние подключения к LiveKit комнате.
///
/// Определение вынесено в [call_session.dart], но реэкспортируется
/// через этот файл для обратной совместимости.
/// Используйте [LiveKitConnectionState] из [call_session.dart].
///
/// Legacy-сервис, теперь выступает фабрикой для [CallSession].
///
/// Каждый звонок создаёт свой экземпляр [CallSession] через [createSession].
/// Это устраняет проблему глобального состояния, когда один звонок мог
/// перезаписывать состояние другого.
class LiveKitService {
  static final LiveKitService _instance = LiveKitService._internal();
  factory LiveKitService() => _instance;
  LiveKitService._internal();

  final ApiService _apiService = ApiService();

  /// Создаёт новый экземпляр [CallSession] для указанного звонка.
  ///
  /// Каждый вызов возвращает новый [CallSession] с изолированным состоянием:
  /// - свой [Room]
  /// - свои [ValueNotifier] для треков и состояния
  /// - свой guard [_isConnecting]
  ///
  /// Вызывающий код (CallService) отвечает за вызов [CallSession.dispose()]
  /// после завершения звонка.
  CallSession createSession(int callId) {
    debugPrint('[LIVEKIT] createSession callId=$callId');
    return CallSession(
      callId: callId,
      apiService: _apiService,
    );
  }
}