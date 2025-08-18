import 'dart:io';
import 'package:synchronized/synchronized.dart';

enum LogLevel { debug, info, warning, error }

class LogUtil {
  static String _logFilePath = '';
  static IOSink? _sink;
  static final Lock _lock = Lock();

  static Future<void> setLogPath(String path) async {
    await _lock.synchronized(() async {
      if (_sink != null) {
        await _sink!.flush();
        await _sink!.close();
        _sink = null;
      }
      _logFilePath = path;
    });
  }

  static Future<void> _init() async {
    if (_logFilePath.isEmpty) return;
    await _lock.synchronized(() async {
      if (_sink == null) {
        final file = File(_logFilePath);
        _sink = file.openWrite(mode: FileMode.append);
      }
    });
  }

  static Future<void> log(String message, {LogLevel level = LogLevel.info}) async {
    if (_logFilePath.isEmpty) return;
    await _init();
    await _lock.synchronized(() async {
      final now = DateTime.now().toIso8601String();
      final levelStr = level.toString().split('.').last.toUpperCase();
      final logLine = '[$now][$levelStr] $message';
      _sink?.writeln(logLine);
      await _sink?.flush();
    });
  }

  static Future<void> debug(String message) => log(message, level: LogLevel.debug);
  static Future<void> info(String message) => log(message, level: LogLevel.info);
  static Future<void> warning(String message) => log(message, level: LogLevel.warning);
  static Future<void> error(String message) => log(message, level: LogLevel.error);

  static Future<void> close() async {
    await _lock.synchronized(() async {
      await _sink?.flush();
      await _sink?.close();
      _sink = null;
    });
  }
}