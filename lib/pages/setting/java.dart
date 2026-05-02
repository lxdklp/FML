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

  late String? _currentJavaPath;

  // 每个设置间的间距
  static const _itemsPadding = Padding(
    padding: EdgeInsets.symmetric(vertical: kDefaultPadding / 2),
  );

  @override
  void initState() {
    super.initState();

    _javaRuntimesFuture = _loadJavaRuntimesFromPrefs();
    _systemDefaultJavaInfo = JavaManager.getSystemDefaultJavaInfo();
  }

  ///
  /// 从SharedPreferences读取缓存的Java列表
  ///
  /// 本处执行的Java搜索不涉及遍历
  ///
  Future<List<JavaRuntime>> _loadJavaRuntimesFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final javaList = prefs.getStringList('javaList') ?? [];

    final List<JavaRuntime> javaRuntimes = [];
    final List<String> validPaths = [];

    _currentJavaPath = prefs.getString('javaSelectedPath');

    // 初次打开/缓存为空，直接执行搜索
    if (javaList.isEmpty) {
      _javaRuntimesFuture = JavaManager.searchPotentialJavaExecutables();
    } else {
      // 遍历缓存的列表
      for (final exe in javaList) {
        final info = await JavaManager.probeJavaExecutable(exe);
        // 检测对应文件是否有效
        if (info != null) {
          final isJdk = await JavaManager.looksLikeJdk(exe);

          javaRuntimes.add(
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
    if (javaRuntimes.isEmpty) {
      return JavaManager.searchPotentialJavaExecutables();
    }

    return javaRuntimes;
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
  /// 写入当前 Java
  ///
  Future<void> _setCurrentJavaPathToPrefs(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('javaSelectedPath', path);

    setState(() {
      _currentJavaPath = path;
    });
  }

  ///
  /// 设置为系统 Java
  ///
  Future<void> _setSystemJava() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('javaSelectedPath');

    setState(() {
      _currentJavaPath = 'default';
    });
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
