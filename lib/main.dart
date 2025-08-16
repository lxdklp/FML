import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

import 'package:fml/pages/home.dart';
import 'package:fml/pages/download.dart';
import 'package:fml/pages/setting.dart';

// 软件版本
const String version = '1.0.0';
const int buildVersion= 1;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static _MyAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>()!;

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;
  Color _themeColor = Colors.blue;
  // 字体可变权重参数（可按需调高/调低）
  static const double bodyWght = 520;     // 正文
  static const double labelWght = 520;    // 标签/按钮
  static const double titleWght = 700;    // 标题
  static const double headlineWght = 850; // 更大标题

  ThemeMode get themeMode => _themeMode;
  Color get themeColor => _themeColor;

  @override
  void initState() {
    super.initState();
    _loadThemePrefs();
  }

  // 加载主题
  Future<void> _loadThemePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString('themeMode');
    final colorInt = prefs.getInt('themeColor');
    if (modeStr != null) {
      switch (modeStr) {
        case 'dark':
          _themeMode = ThemeMode.dark;
          break;
        case 'light':
          _themeMode = ThemeMode.light;
          break;
        default:
          _themeMode = ThemeMode.system;
      }
    }
    if (colorInt != null) {
      _themeColor = Color(colorInt);
    }
    if (mounted) setState(() {});
  }

  Future<void> changeTheme(ThemeMode themeMode) async {
    setState(() {
      _themeMode = themeMode;
    });
    final prefs = await SharedPreferences.getInstance();
    String modeStr;
    switch (themeMode) {
      case ThemeMode.dark:
        modeStr = 'dark';
        break;
      case ThemeMode.light:
        modeStr = 'light';
        break;
      default:
        modeStr = 'system';
    }
    await prefs.setString('themeMode', modeStr);
  }

  Future<void> changeThemeColor(Color color) async {
    setState(() {
      _themeColor = color;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeColor', color.value);
  }

  // ===== 可变字体权重统一处理 =====
  TextTheme _withVariableWeights(TextTheme base) {
    TextStyle setW(TextStyle? s, double w) => (s ?? const TextStyle()).copyWith(
          fontFamily: 'NotoSans',
          fontVariations: [FontVariation('wght', w)],
        );
    return base.copyWith(
      bodySmall: setW(base.bodySmall, bodyWght),
      bodyMedium: setW(base.bodyMedium, bodyWght),
      bodyLarge: setW(base.bodyLarge, bodyWght),
      labelSmall: setW(base.labelSmall, labelWght),
      labelMedium: setW(base.labelMedium, labelWght),
      labelLarge: setW(base.labelLarge, labelWght),
      titleSmall: setW(base.titleSmall, titleWght),
      titleMedium: setW(base.titleMedium, titleWght),
      titleLarge: setW(base.titleLarge, titleWght),
      headlineSmall: setW(base.headlineSmall, headlineWght),
      headlineMedium: setW(base.headlineMedium, headlineWght),
      headlineLarge: setW(base.headlineLarge, headlineWght),
      displaySmall: setW(base.displaySmall, headlineWght),
      displayMedium: setW(base.displayMedium, headlineWght),
      displayLarge: setW(base.displayLarge, headlineWght),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _themeColor,
      brightness: brightness,
    );
    final baseTypography = Typography.material2021();
    final raw = brightness == Brightness.dark ? baseTypography.white : baseTypography.black;
    final textTheme = _withVariableWeights(raw);
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSans',
      fontFamilyFallback: const ['Microsoft YaHei', 'Segoe UI', 'Arial'],
      colorScheme: scheme,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge,
        elevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        selectedLabelTextStyle: textTheme.labelLarge,
        unselectedLabelTextStyle: textTheme.labelMedium,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Minecraft Launcher',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _themeMode,
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;
  bool? _javaInstalled;

  @override
  void initState() {
    super.initState();
    _writeVersionInfo();
    _checkJavaInstalled();
  }

  // 写入版本信息
  Future<void> _writeVersionInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('version', version);
    await prefs.setInt('build', buildVersion);
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 1:
        return const DownloadPage();
      case 2:
        return const SettingPage();
      case 0:
      default:
        return const HomePage();
    }
  }

  // 检查是否安装Java
  Future<void> _checkJavaInstalled() async {
    try {
      final result = await Process.run('java', ['-version']);
      setState(() {
        _javaInstalled = result.exitCode == 0;
      });
      if (_javaInstalled == false) {
        _showJavaNotFoundDialog();
      }
    } catch (e) {
      setState(() {
        _javaInstalled = false;
      });
      _showJavaNotFoundDialog();
    }
  }

  void _showJavaNotFoundDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('未检测到 Java'),
          content: const Text('未检测到 Java 环境或者 Java 环境未正确配置，请先安装 Java 后再打开启动器'),
          actions: [
            TextButton(
              onPressed: () => _launchJavaURL(),
              child: const Text('打开Java下载页面'),
            ),
          ],
        ),
      );
    });
  }

  // 打开Java
  Future<void> _launchJavaURL() async {
    try {
      final Uri uri = Uri.parse('https://www.oracle.com/cn/java/technologies/downloads/');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发生错误: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter MInecraft Launcher')),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() => _selectedIndex = index);
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.play_arrow),
                label: Text('启动'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.download),
                label: Text('下载'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('设置'),
              ),
            ],
          ),
          Expanded(
            child: Center(child: _buildPage(_selectedIndex)),
          ),
        ],
      ),
    );
  }
}