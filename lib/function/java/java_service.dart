import 'package:fml/function/java/java_utils.dart';
import 'package:fml/function/java/models/java_info.dart';
import 'package:fml/function/java/models/java_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

class JavaService {
  JavaService._();

  static List<JavaRuntime> _javaRuntimes = [];
  static List<JavaRuntime> get javaRuntimes => _javaRuntimes;

  static String _currentJavaPath = '';
  static String get currentJavaPath => _currentJavaPath;

  static JavaInfo? _systemDefaultJavaInfo;
  static JavaInfo? get systemDefaultJavaInfo => _systemDefaultJavaInfo;

  static Future<void> init() async {
    _systemDefaultJavaInfo = await JavaUtils.getSystemDefaultJavaInfo();

    final prefs = await SharedPreferences.getInstance();
    final javaList = prefs.getStringList('javaList') ?? [];

    final List<String> validPaths = [];

    // 初次打开/缓存为空，直接执行搜索
    if (javaList.isEmpty) {
      _javaRuntimes = await JavaUtils.searchPotentialJavaExecutables();
    } else {
      // 遍历缓存的列表
      for (final exe in javaList) {
        final info = await JavaUtils.probeJavaExecutable(exe);
        // 检测对应文件是否有效
        if (info != null) {
          final isJdk = await JavaUtils.looksLikeJdk(exe);

          _javaRuntimes.add(
            JavaRuntime(info: info, executable: exe, isJdk: isJdk),
          );

          validPaths.add(exe);
        }
      }
    }

    // 缓存内java列表出现了变化，再次写入SharedPreferences
    if (validPaths.length != javaList.length) {
      await prefs.setStringList('javaList', validPaths);
    }

    // 缓存内路径全部失效，搜索Java
    if (_javaRuntimes.isEmpty) {
      _javaRuntimes = await JavaUtils.searchPotentialJavaExecutables();
    }

    /// 处理_currentJavaPath
    _currentJavaPath = prefs.getString('javaSelectedPath') ?? '';

    if (_currentJavaPath.isEmpty) {
      if (_systemDefaultJavaInfo != null) {
        _currentJavaPath = _systemDefaultJavaInfo.path;
      }
    }
  }

  ///
  /// 写入当前 Java
  ///
  static Future<void> setCurrentJavaPathToPrefs(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('javaSelectedPath', path);

    _currentJavaPath = path;
  }

  ///
  /// 设置为系统 Java
  ///
  static Future<void> setSystemJava() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('javaSelectedPath');

    _currentJavaPath = 'default';
  }
}
