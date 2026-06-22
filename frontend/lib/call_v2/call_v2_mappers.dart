import 'call_event.dart';
import '../notifications_v2/notification_event_v2.dart';

/// Mapper-функции из legacy payload → V2 events.
///
/// Вынесены отдельно, чтобы call_service.dart и push_service.dart
/// не засорялись логикой преобразования.

class CallV2Mappers {
  /// Из socket payload входящего звонка → ReceiveIncomingEvent.
  static ReceiveIncomingEvent incomingFromSocket(Map<String, dynamic> payload) {
    return ReceiveIncomingEvent(
      callerUserId: payload['callerId'] as int? ?? 0,
      callId: payload['callId'] as int? ?? 0,
      callType: payload['callType'] as String?,
      callerName: payload['callerName'] as String?,
    );
  }

  /// Из данных исходящего звонка → StartOutgoingEvent.
  static StartOutgoingEvent outgoingFromData({
    required int calleeId,
    String? callType,
    int? callId,
  }) {
    return StartOutgoingEvent(
      calleeId: calleeId,
      callType: callType,
      callId: callId,
    );
  }

  /// Из socket payload подтверждения → RemoteAcceptedEvent.
  static RemoteAcceptedEvent remoteAcceptedFromSocket(Map<String, dynamic> payload) {
    return RemoteAcceptedEvent(
      remoteCallId: payload['callId'] as int? ?? 0,
    );
  }

  /// Из socket payload завершения → RemoteEndEvent.
  static RemoteEndEvent remoteEndFromSocket(Map<String, dynamic> payload) {
    return RemoteEndEvent(
      reason: payload['reason'] as String?,
    );
  }

  /// Из данных таймаута → TimeoutNoAnswerEvent.
  static TimeoutNoAnswerEvent timeoutFromData(String direction) {
    return TimeoutNoAnswerEvent(direction: direction);
  }

  /// Из push payload → NotificationTransportEventV2.
  static NotificationTransportEventV2 transportFromPush({
    required String payload,
    required bool isForeground,
    String? notificationId,
  }) {
    return NotificationTransportEventV2(
      transportType: isForeground
          ? NotificationTransportTypeV2.pushForeground
          : NotificationTransportTypeV2.pushBackground,
      payload: payload,
      notificationId: notificationId,
    );
  }
}