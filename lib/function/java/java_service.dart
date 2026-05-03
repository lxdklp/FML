import 'dart:convert';
import 'dart:io';

import 'package:fml/function/java/java_utils.dart';
import 'package:fml/function/java/models/java_info.dart';
import 'package:fml/function/java/models/java_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

class JavaService {
  JavaService._();

  static List<JavaRuntime> _javaRuntimes = [];
  static List<JavaRuntime> get javaRuntimes => _javaRuntimes;

  static String _javaSelectedPath = '';
  static String get javaSelectedPath => _javaSelectedPath;

  static JavaInfo? _systemDefaultJavaInfo;
  static JavaInfo? get systemDefaultJavaInfo => _systemDefaultJavaInfo;

  static late final Future<void> initFuture;

  static Future<void> init() async {
    final futures = await Future.wait([
      JavaUtils.getSystemDefaultJavaInfo(),
      SharedPreferences.getInstance(),
    ]);

    _systemDefaultJavaInfo = futures[0] as JavaInfo?;
    SharedPreferences prefs = futures[1] as SharedPreferences;

    final cachedJson = prefs.getString('javaRuntimes') ?? '';
    final systemJavaInfo = _systemDefaultJavaInfo;
    final List<String> validPaths = [];

    _javaRuntimes = [];

    late final List<JavaRuntime> cachedRuntimes;

    if (cachedJson.isEmpty) {
      // 初次打开/缓存为空，直接执行搜索并写入
      _javaRuntimes = await JavaUtils.searchPotentialJavaExecutables();
      writeRuntimesToPrefs(prefs, _javaRuntimes);
    } else {
      cachedRuntimes = await readRuntimesFromPrefs(cachedJson);

      // 遍历缓存的列表
      for (final javaRuntime in cachedRuntimes) {
        // 仅检测对应文件是否存在
        if (await File(javaRuntime.executable).exists()) {
          _javaRuntimes.add(javaRuntime);
          validPaths.add(javaRuntime.executable);
        }
      }
    }

    // 缓存内java列表出现了变化，再次写入SharedPreferences
    if (cachedJson.isNotEmpty && validPaths.length != cachedRuntimes.length) {
      writeRuntimesToPrefs(prefs, _javaRuntimes);
    }

    // 缓存内路径全部失效，搜索Java
    if (_javaRuntimes.isEmpty) {
      _javaRuntimes = await JavaUtils.searchPotentialJavaExecutables();

      writeRuntimesToPrefs(prefs, _javaRuntimes);
    }

    /// 处理_currentJavaPath
    _javaSelectedPath = prefs.getString('javaSelectedPath') ?? '';

    // 若不存在/为空，设置为系统java，若系统java也不存在，设置为扫描到的第一个JavaRuntime
    if (_javaSelectedPath.isEmpty) {
      if (systemJavaInfo != null) {
        _javaSelectedPath = systemJavaInfo.path;
      } else if (javaRuntimes.isNotEmpty) {
        _javaSelectedPath = _javaRuntimes.first.executable;
      }

      prefs.setString('javaSelectedPath', _javaSelectedPath);
    } else {
      // 缓存的java已无效，重复上方逻辑
      final info = await JavaUtils.probeJavaExecutable(_javaSelectedPath);

      if (info == null) {
        if (systemJavaInfo != null) {
          _javaSelectedPath = systemJavaInfo.path;
        } else if (javaRuntimes.isNotEmpty) {
          _javaSelectedPath = _javaRuntimes.first.executable;
        }

        prefs.setString('javaSelectedPath', _javaSelectedPath);
      }
    }
  }

  ///
  /// 将JavaRuntimes列表序列化为JSON字符串并写入
  ///
  static Future<void> writeRuntimesToPrefs(
    SharedPreferences prefs,
    List<JavaRuntime> javaRuntimes,
  ) async {
    final List<Map<String, dynamic>> mapList = javaRuntimes
        .map((e) => e.toJson())
        .toList();

    final jsonString = jsonEncode(mapList);

    await prefs.setString('javaRuntimes', jsonString);
  }

  ///
  /// 从JSON字符串反序列化出存储的JavaRuntimes列表
  ///
  static Future<List<JavaRuntime>> readRuntimesFromPrefs(String input) async {
    final List<dynamic> decoded = jsonDecode(input);

    return decoded
        .map((e) => JavaRuntime.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  ///
  /// 写入当前所选的Java
  ///
  static Future<void> setSelectedJavaPathToPrefs(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('javaSelectedPath', path);

    _javaSelectedPath = path;
  }

  ///
  /// 刷新JavaRuntimes
  ///
  static Future<void> refreshJavaRuntimes() async {
    final freshList = await JavaUtils.searchPotentialJavaExecutables();

    _javaRuntimes = freshList;

    final prefs = await SharedPreferences.getInstance();

    await writeRuntimesToPrefs(prefs, freshList);
  }

  static set javaSelectedPath(String newPath) {
    if (newPath == _javaSelectedPath) return;

    final newFile = File(newPath);

    if (!newFile.existsSync()) {
      throw ArgumentError('路径不存在: $newPath');
    }

    _javaSelectedPath = newPath;
  }
}
