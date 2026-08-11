import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';

/// Простой логгер для диагностики видеозвонков.
/// Пишет временные метки и сообщения в текстовый файл на устройстве.
/// Файл создаётся в app-документ-директории (гарантированно работает на Android 11+).
/// При закрытии пытается скопировать в Downloads для удобства пользователя.
/// Новый файл создаётся на каждый звонок.
class CallLogger {
  static final CallLogger _instance = CallLogger._internal();
  factory CallLogger() => _instance;
  CallLogger._internal();

  IOSink? _sink;
  String? _currentFilePath;
  bool _isInitialized = false;

  /// Путь к текущему лог-файлу (для отладки/отчёта)
  String? get currentFilePath => _currentFilePath;

  /// Инициализирует логгер: создаёт новый файл с timestamp.
  /// Вызывается при старте звонка.
  Future<void> init() async {
    await _closeSink();

    try {
      // Используем app-документ-директорию — гарантированно работает
      final dir = await getApplicationDocumentsDirectory();
      print('[CALL_LOGGER] Using directory: ${dir.path}');

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final fileName = 'napp_call_log_$timestamp.txt';
      final file = File('${dir.path}/$fileName');
      _sink = file.openWrite(mode: FileMode.write);
      _currentFilePath = file.path;
      _isInitialized = true;

      print('[CALL_LOGGER] ✅ Log file created: $_currentFilePath');
      _write('=== CALL LOG START ===');
      _write('File: $_currentFilePath');
      _write('Device timestamp: ${DateTime.now().toIso8601String()}');
    } catch (e) {
      print('[CALL_LOGGER] ❌ Failed to init log file: $e');
      _isInitialized = false;
    }
  }

  /// Пишет строку в лог-файл с временной меткой и источником.
  void log(String source, String message) {
    if (!_isInitialized || _sink == null) return;
    final timestamp = DateTime.now().toIso8601String();
    _write('[$timestamp] [$source] $message');
  }

  /// Пишет ошибку с префиксом [ERROR].
  void error(String source, String message) {
    log(source, '❌ ERROR: $message');
  }

  /// Пишет предупреждение.
  void warn(String source, String message) {
    log(source, '⚠️ WARN: $message');
  }

  /// Закрывает лог-файл. Вызывается при завершении звонка.
  Future<void> close() async {
    if (!_isInitialized) return;
    _write('=== CALL LOG END ===');
    await _closeSink();
    // Пытаемся скопировать в Downloads
    await _copyToDownloads();
    _isInitialized = false;
  }

  /// Копирует лог-файл в Downloads/ для удобства доступа пользователя.
  Future<void> _copyToDownloads() async {
    if (_currentFilePath == null) return;
    try {
      final sourceFile = File(_currentFilePath!);
      if (!await sourceFile.exists()) return;

      final downloadDir = await getDownloadsDirectory();
      if (downloadDir != null) {
        final destFileName = _currentFilePath!.split('/').last;
        final destFile = File('${downloadDir.path}/$destFileName');
        await sourceFile.copy(destFile.path);
        print('[CALL_LOGGER] ✅ Copied to Downloads: ${destFile.path}');
      } else {
        print('[CALL_LOGGER] ⚠️ Downloads directory not available (scoped storage)');
        print('[CALL_LOGGER] 📁 Log file is at: $_currentFilePath');
        print('[CALL_LOGGER] 💡 To access: adb shell run-as com.napp.app cat $_currentFilePath');
      }
    } catch (e) {
      print('[CALL_LOGGER] ⚠️ Failed to copy to Downloads: $e');
      print('[CALL_LOGGER] 📁 Log file is at: $_currentFilePath');
    }
  }

  void _write(String line) {
    try {
      _sink?.writeln(line);
    } catch (_) {
      // Игнорируем ошибки записи — не должны ломать звонок
    }
  }

  Future<void> _closeSink() async {
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
    _currentFilePath = null;
  }
}