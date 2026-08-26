import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class LogUtil {

  // 解析调用信息
  static String _resolveCaller() {
    final stack = StackTrace.current.toString().split('\n');
    String? line;
    for (final l in stack) {
      if (l.contains('package:') && !l.contains('log.dart')) {
        line = l;
        break;
      }
    }
    if (line == null) return 'unknown';
    final match = RegExp(r'package:([^/]+)/(.+\.dart):(\d+)').firstMatch(line);
    if (match != null) {
      final filepath = match.group(2) ?? 'unknown';
      final lineNum = match.group(3) ?? 'unknown';
      return '$filepath:$lineNum';
    }
    return 'unknown';
  }

  // 添加日志
  static Future<void> log(String message, {String level = 'INFO'}) async {
    final caller = _resolveCaller();
    debugPrint('[$level] [$caller] $message');
    final prefs = await SharedPreferences.getInstance();
    // 过滤日志
    final int logLevel = prefs.getInt('logLevel') ?? 0;
    if ((level == 'INFO' && logLevel > 0) ||
        (level == 'WARNING' && logLevel > 1)) {
      return;
    }
    List<String> logs = prefs.getStringList('logs') ?? [];
    // 创建日志条目
    final timestamp = DateTime.now().toIso8601String();
    final logEntry = jsonEncode({
      'timestamp': timestamp,
      'level': level,
      'caller': caller,
      'message': message,
    });
    logs.add(logEntry);
    await prefs.setStringList('logs', logs);
  }

  // 获取所有日志
  static Future<List<Map<String, dynamic>>> getLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final logs = prefs.getStringList('logs') ?? [];
    return logs.map((log) => jsonDecode(log) as Map<String, dynamic>).toList();
  }

  // 清除所有日志
  static Future<void> clearLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('logs');
  }
}