import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fml/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fml/function/log.dart';
import 'package:fml/function/java/java_manager.dart';
import 'package:fml/function/java/models/java_info.dart';
import 'package:fml/function/java/models/java_runtime.dart';

class JavaPage extends StatefulWidget {
  const JavaPage({super.key});

  @override
  JavaPageState createState() => JavaPageState();
}

class JavaPageState extends State<JavaPage> {
  late Future<List<JavaRuntime>> _javaRuntimesFuture;
  late Future<JavaInfo?> _systemDefaultJavaInfo;

  String? _currentJavaPath;

  // 每个设置间的间距
  static const _itemsPadding = Padding(
    padding: EdgeInsets.symmetric(vertical: kDefaultPadding / 2),
  );

  @override
  void initState() {
    super.initState();
    _getCurrentJavaPathFromPrefs();
    _refresh();
  }

  ///
  /// 刷新 Java 列表与系统默认 Java
  ///
  Future<void> _refresh() async {
    setState(() {
      _systemDefaultJavaInfo = _getSystemDefaultJavaInfo();
      _javaRuntimesFuture = JavaManager.searchPotentialJavaExecutables();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kDefaultPadding),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          // 大标题
          Padding(
            padding: const EdgeInsets.only(
              left: kDefaultPadding / 2,
              top: kDefaultPadding,
              bottom: kDefaultPadding,
            ),
            child: Text(
              '设备上的Java列表',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),

          _itemsPadding,

          // 确保FutureBuilder占满剩余空间
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: Future.wait([
                _systemDefaultJavaInfo,
                _javaRuntimesFuture,
              ]),

              builder: (context, snapshot) {
                // 加载中显示CircularProgressIndicator
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                // 加载失败显示错误信息
                // TODO: 包装一个表示错误的组件
                if (snapshot.hasError) {
                  return Center(child: Text('检测失败：${snapshot.error}'));
                }

                // Index0: _systemDefaultJavaInfo 的结果（JavaInfo?）
                // Index1: _javaRuntimesFuture 的结果（List<JavaRuntime>）
                final results = snapshot.data ?? [];

                // 提取系统默认 Java 信息
                final JavaInfo? systemJavaInfo = results.isNotEmpty
                    ? results[0] as JavaInfo?
                    : null;

                // 检测系统默认Java是否存在
                final systemJavaExists = systemJavaInfo != null;

                // 提取扫描到的Java运行时列表
                List<JavaRuntime> javaRuntimes = [];
                if (results.length > 1) {
                  javaRuntimes = (results[1] as List).cast<JavaRuntime>();
                }

                // 如果系统默认存在且路径不为空，移除扫描列表中与系统默认路径相同的项
                if (systemJavaInfo != null && systemJavaInfo.path.isNotEmpty) {
                  javaRuntimes.removeWhere(
                    (runtime) => runtime.executable == systemJavaInfo.path,
                  );
                }

                final totalItems = systemJavaExists
                    ? javaRuntimes.length + 1
                    : javaRuntimes.length;

                if (totalItems == 0) {
                  return const Center(child: Text('未检测到 Java'));
                }

                return ListView.builder(
                  itemCount: totalItems,

                  itemBuilder: (context, index) {
                    if (systemJavaExists && index == 0) {
                      final isCurrentJava =
                          _currentJavaPath == 'default' ||
                          _currentJavaPath == null;

                      // 构建系统默认Card
                      return _buildJavaCard(
                        javaInfo: systemJavaInfo,

                        typeChipLabel: '系统默认',

                        vendor: systemJavaInfo.vendor,

                        isCurrent: isCurrentJava,

                        onTap: _setSystemJava,
                      );
                    }

                    // 构建非系统默认的Java的卡片
                    final realIndex = systemJavaExists ? index - 1 : index;
                    final javaRuntime = javaRuntimes[realIndex];

                    final isCurrentJava =
                        _currentJavaPath == javaRuntime.executable;

                    return _buildJavaCard(
                      javaInfo: javaRuntime.info,

                      typeChipLabel: javaRuntime.isJdk ? 'JDK' : 'JRE',

                      vendor: javaRuntime.info.vendor,

                      isCurrent: isCurrentJava,

                      onTap: () =>
                          _setCurrentJavaPathToPrefs(javaRuntime.executable),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  ///
  /// 从SharedPreferences读取选择的Java
  ///
  Future<void> _getCurrentJavaPathFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _currentJavaPath = prefs.getString('java');
    });
  }

  ///
  /// 写入当前 Java
  ///
  Future<void> _setCurrentJavaPathToPrefs(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('java', path);

    setState(() {
      _currentJavaPath = path;
    });
  }

  ///
  /// 设置为系统 Java
  ///
  Future<void> _setSystemJava() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('java');

    setState(() {
      _currentJavaPath = 'default';
    });
  }

  //
  // 获取系统默认 Java 信息
  //
  Future<JavaInfo?> _getSystemDefaultJavaInfo() async {
    try {
      final javaVersionProcess = await Process.run('java', ['-version']);

      if (javaVersionProcess.exitCode != 0) {
        LogUtil.log(
          '获取系统默认 Java 信息失败，退出码：${javaVersionProcess.exitCode}',
          level: 'WARN',
        );
      }

      final versionOutput = (javaVersionProcess.stderr as String).isNotEmpty
          ? javaVersionProcess.stderr as String
          : javaVersionProcess.stdout as String;

      final parsedVersion = JavaManager.parseVersionOutput(versionOutput);

      if (parsedVersion == null) {
        LogUtil.log('无法解析系统默认 Java 版本信息', level: 'WARN');
        return null;
      }

      String executablePath = '';

      try {
        if (Platform.isWindows) {
          final where = await Process.run('where', ['java']);

          if (where.exitCode == 0) {
            executablePath = (where.stdout as String)
                .toString()
                .split('\n')
                .first
                .trim();
          }
        } else {
          final which = await Process.run('which', ['java']);

          if (which.exitCode == 0) {
            executablePath = (which.stdout as String)
                .toString()
                .split('\n')
                .first
                .trim();
          }
        }
      } catch (e) {
        LogUtil.log('获取系统默认 Java 路径时出错：$e', level: 'WARN');
      }

      return JavaInfo(
        version: parsedVersion['version'] ?? 'unknown',
        vendor: parsedVersion['vendor'],
        path: executablePath,
        os: Platform.operatingSystem,
        arch: Platform.version,
      );
    } catch (e) {
      LogUtil.log('执行 "java -version" 时出错：$e', level: 'WARN');
      return null;
    }
  }

  Widget _buildJavaCard({
    required JavaInfo javaInfo,
    required String typeChipLabel,
    String? vendor,
    required bool isCurrent,
    required VoidCallback onTap,
  }) {
    return Card(
      // 裁剪掉ListTile超出圆角的部分
      clipBehavior: Clip.antiAlias,

      elevation: 0,

      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),

      // 为当前Java时高亮
      color: isCurrent
          ? Theme.of(context).colorScheme.secondaryContainer
          : null,

      child: ListTile(
        title: Text(javaInfo.version),

        subtitle: Text(javaInfo.path.isNotEmpty ? javaInfo.path : '路径未知'),

        trailing: Row(
          mainAxisSize: MainAxisSize.min,

          children: [
            if (isCurrent) ...[
              Chip(label: Text('当前')),

              SizedBox(width: kDefaultPadding / 2),
            ],
            Chip(label: Text(typeChipLabel)),

            SizedBox(width: kDefaultPadding / 2),

            Chip(label: Text(vendor ?? 'Unknown')),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
