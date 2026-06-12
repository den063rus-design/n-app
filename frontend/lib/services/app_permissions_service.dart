import 'package:permission_handler/permission_handler.dart';

class AppPermissionsService {
  static final AppPermissionsService _instance = AppPermissionsService._internal();
  factory AppPermissionsService() => _instance;
  AppPermissionsService._internal();

  /// Запросить все первичные разрешения при первом запуске
  Future<void> requestInitialPermissions() async {
    await _requestNotificationPermission();
    await _requestCameraPermission();
    await _requestMicrophonePermission();
    await _requestMediaPermissions();
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.request();
    // Не падаем, если пользователь отказал
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
  }

  Future<void> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
  }

  Future<void> _requestMediaPermissions() async {
    // Приложение работает с фото (галерея через FilePicker),
    // видео (галерея через FilePicker, видеозвонки через WebRTC),
    // аудио (голосовые сообщения через record, аудиозвонки через WebRTC).
    //
    // На Android 13+ для доступа к медиафайлам нужны отдельные permissions:
    // - Permission.photos       → READ_MEDIA_IMAGES  (фото из галереи)
    // - Permission.videos       → READ_MEDIA_VIDEO   (видео из галереи)
    // - Permission.audio        → READ_MEDIA_AUDIO   (аудиофайлы)
    //
    // Для документов (FilePicker) отдельный runtime permission не нужен —
    // FilePicker сам управляет доступом нативно.
    //
    // Камера и микрофон запрашиваются отдельно в _requestCameraPermission()
    // и _requestMicrophonePermission().

    await Permission.photos.request();
    await Permission.videos.request();
    await Permission.audio.request();
  }
}