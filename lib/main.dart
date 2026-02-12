import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:fml/function/dio_client.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'package:fml/constants.dart';
import 'package:fml/function/log.dart';
import 'package:fml/pages/download.dart';
import 'package:fml/pages/home.dart';
import 'package:fml/pages/online.dart';
import 'package:fml/pages/online/owner.dart';
import 'package:fml/pages/setting.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initVersionInfo();
  await initLogs();

  runApp(const FMLBaseApp());
}

// 软件版本
Future<void> initVersionInfo() async {
  final packageInfo = await PackageInfo.fromPlatform();

  gAppVersion = packageInfo.version;
  gAppUserAgent = 'FML/$gAppVersion';
  gAppBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('version', gAppVersion);
  await prefs.setInt('build', gAppBuildNumber);
}

// 日志
Future<void> initLogs() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final bool autoClearLog = prefs.getBool('autoClearLog') ?? true;
  if (autoClearLog) {
    await LogUtil.clearLogs();
  }

  await LogUtil.log(
    '启动FML, 平台:${Platform.operatingSystem}, 版本: $gAppVersion, 构建号: $gAppBuildNumber${kDebugMode ? ", debug模式" : ""}',
    level: 'INFO',
  );
}

class FMLBaseApp extends StatefulWidget {
  const FMLBaseApp({super.key});

  static FMLBaseAppState of(BuildContext context) =>
      context.findAncestorStateOfType<FMLBaseAppState>()!;

  @override
  FMLBaseAppState createState() => FMLBaseAppState();
}

class FMLBaseAppState extends State<FMLBaseApp> {
  ThemeMode _themeMode = ThemeMode.system;
  Color _themeColor = Colors.blue;

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
    if (colorInt != null) {
      // 从存储的整数值创建颜色对象
      _themeColor = Color.fromARGB(
        (colorInt >> 24) & 0xFF,
        (colorInt >> 16) & 0xFF,
        (colorInt >> 8) & 0xFF,
        colorInt & 0xFF,
      );
    }
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
    int colorValue =
        (((color.a * 255.0).round() & 0xFF) << 24) |
        (((color.r * 255.0).round() & 0xFF) << 16) |
        (((color.g * 255.0).round() & 0xFF) << 8) |
        ((color.b * 255.0).round() & 0xFF);
    await prefs.setInt('themeColor', colorValue);
  }

  // 可变字体权重
  TextTheme _withVariableWeights(TextTheme base) {
    TextStyle setW(TextStyle? s, double w) => (s ?? const TextStyle()).copyWith(
      fontFamily: 'NotoSans',
      fontVariations: [FontVariation('wght', w)],
    );
    return base.copyWith(
      bodySmall: setW(base.bodySmall, AppFontWeights.bodyWght),
      bodyMedium: setW(base.bodyMedium, AppFontWeights.bodyWght),
      bodyLarge: setW(base.bodyLarge, AppFontWeights.bodyWght),
      labelSmall: setW(base.labelSmall, AppFontWeights.labelWght),
      labelMedium: setW(base.labelMedium, AppFontWeights.labelWght),
      labelLarge: setW(base.labelLarge, AppFontWeights.labelWght),
      titleSmall: setW(base.titleSmall, AppFontWeights.titleWght),
      titleMedium: setW(base.titleMedium, AppFontWeights.titleWght),
      titleLarge: setW(base.titleLarge, AppFontWeights.titleWght),
      headlineSmall: setW(base.headlineSmall, AppFontWeights.headlineWght),
      headlineMedium: setW(base.headlineMedium, AppFontWeights.headlineWght),
      headlineLarge: setW(base.headlineLarge, AppFontWeights.headlineWght),
      displaySmall: setW(base.displaySmall, AppFontWeights.headlineWght),
      displayMedium: setW(base.displayMedium, AppFontWeights.headlineWght),
      displayLarge: setW(base.displayLarge, AppFontWeights.headlineWght),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _themeColor,
      brightness: brightness,
    );
    final baseTypography = Typography.material2021();
    final raw = brightness == Brightness.dark
        ? baseTypography.white
        : baseTypography.black;
    final textTheme = _withVariableWeights(raw);
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSans',
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
      title: kAppName,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _themeMode,
      home: const MainStartPage(),
      onGenerateRoute: (settings) {
        if (settings.name == kOnlineOwnerRoute) {
          final int port = settings.arguments as int;
          final String etServer = settings.arguments as String;
          return SlidePageRoute(
            page: OwnerPage(port: port, etServer: etServer),
          );
        }
        return null;
      },
    );
  }
}

class MainStartPage extends StatefulWidget {
  const MainStartPage({super.key});
  @override
  MainStartPageState createState() => MainStartPageState();
}

class MainStartPageState extends State<MainStartPage> {
  int _selectedIndex = 0;
  bool? _javaInstalled;

  @override
  void initState() {
    super.initState();
    _checkJavaInstalled();
    _checkUpdate();
  }

  // 构建页面
  Widget _buildPage(int index) {
    switch (index) {
      case 1:
        return const OnlinePage();
      case 2:
        return const DownloadPage();
      case 3:
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

  // 显示Java未找到的对话框
  Future<void> _showJavaNotFoundDialog() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('未检测到 Java'),
          content: const Text('未检测到 Java 环境或者 Java 环境未正确配置，请先安装 Java 后再打开启动器'),
          actions: [
            TextButton(
              onPressed: () => _launchURL(AppUrls.javaDownload),
              child: const Text('打开Java下载页面'),
            ),
          ],
        ),
      );
    });
  }

  // 打开URL
  Future<void> _launchURL(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return; // 添加 mounted 检查
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法打开链接: $url')));
      }
    } catch (e) {
      if (!mounted) return; // 添加 mounted 检查
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发生错误: $e')));
    }
  }

  // 检查更新
  Future<void> _checkUpdate() async {
    try {
      LogUtil.log('正在检查更新', level: 'INFO');

      final response = await DioClient().dio.get(AppUrls.latestVersionApi);

      if (response.statusCode == 200) {
        String rawVersionData = response.data.toString();
        String cleanedVersionString = rawVersionData
            .replaceAll("[", "")
            .replaceAll("]", "");
        final int latestVersion =
            int.tryParse(cleanedVersionString) ?? gAppBuildNumber;
        LogUtil.log('最新版本: $latestVersion');

        if (latestVersion > gAppBuildNumber && mounted) {
          _showUpdateDialog(latestVersion.toString());
        }
      }
    } catch (e) {
      LogUtil.log(e.toString(), level: 'ERROR');
    }
  }

  // 获取更新日志
  Future<List<String>> _getUpdateInfo() async {
    try {
      final response = await DioClient().dio.get(AppUrls.githubReleasesApi);

      if (response.statusCode == 200) {
        Map<String, dynamic> loaderData = response.data[0];
        return [loaderData['name'], loaderData['body']];
      }
    } catch (e) {
      LogUtil.log('获取更新日志失败: $e', level: 'ERROR');
      return ['', '请前往 GitHub 查看更新日志'];
    }
    return ['', '请前往 GitHub 查看更新日志'];
  }

  // 显示更新对话框
  Future<void> _showUpdateDialog(String latestVersion) async {
    List<String> info = await _getUpdateInfo();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('发现新版本 ${info[0]}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: SingleChildScrollView(
            child: Markdown(
              data: info[1],
              selectable: true,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onTapLink: (text, href, title) {
                if (href != null) _launchURL(href);
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              _launchURL(AppUrls.githubLatestRelease);
            },
            child: const Text('前往GitHub下载'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 主界面内容
    Widget mainContent = Scaffold(
      appBar: AppBar(title: const Text(kAppName)),
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
                icon: Icon(Icons.hub),
                label: Text('联机'),
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
          Expanded(child: Center(child: _buildPage(_selectedIndex))),
        ],
      ),
    );
    // macOS 菜单栏
    if (Platform.isMacOS) {
      return PlatformMenuBar(
        menus: [
          // FML 菜单
          PlatformMenu(
            label: kAppName,
            menus: [
              PlatformMenuItem(
                label: '关于',
                onSelected: () => _showAboutDialog(context),
              ),
              PlatformMenuItem(label: '检查更新', onSelected: () => _checkUpdate()),
              PlatformMenuItem(
                label: '设置',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.comma,
                  meta: true,
                ),
                onSelected: () => setState(() => _selectedIndex = 3),
              ),
              PlatformMenuItem(
                label: '退出',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyQ,
                  meta: true,
                ),
                onSelected: () => SystemNavigator.pop(),
              ),
            ],
          ),
          // 导航菜单
          PlatformMenu(
            label: '导航',
            menus: [
              PlatformMenuItem(
                label: '启动',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.digit1,
                  meta: true,
                ),
                onSelected: () => setState(() => _selectedIndex = 0),
              ),
              PlatformMenuItem(
                label: '联机',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.digit2,
                  meta: true,
                ),
                onSelected: () => setState(() => _selectedIndex = 1),
              ),
              PlatformMenuItem(
                label: '下载',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.digit3,
                  meta: true,
                ),
                onSelected: () => setState(() => _selectedIndex = 2),
              ),
              PlatformMenuItem(
                label: '设置',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.digit4,
                  meta: true,
                ),
                onSelected: () => setState(() => _selectedIndex = 3),
              ),
            ],
          ),
          // 帮助菜单
          PlatformMenu(
            label: '帮助',
            menus: [
              PlatformMenuItem(
                label: '访问 GitHub',
                onSelected: () => _launchURL(AppUrls.githubProject),
              ),
            ],
          ),
        ],
        child: mainContent,
      );
    }
    return mainContent;
  }

  // 显示关于对话框
  Future<void> _showAboutDialog(BuildContext context) async {
    const channel = MethodChannel(kNativeMethodChannel);
    await channel.invokeMethod('showAboutPanel');
  }
}
