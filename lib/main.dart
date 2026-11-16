import 'package:fml/function/config/account_credentials.dart';
import 'package:fml/function/config/game_config_validator.dart';
import 'package:fml/function/crypto_util.dart';
import 'package:fml/pages/startup/game_config_check.dart';

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:fml/function/java/java_service.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:fml/function/dio_client.dart';
import 'package:lazy_load_indexed_stack/lazy_load_indexed_stack.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:fml/function/config/app_config.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'package:fml/constants.dart';
import 'package:fml/function/log.dart';
import 'package:fml/pages/download_page.dart';
import 'package:fml/pages/home_page.dart';
import 'package:fml/pages/home/management/patchpack.dart';
import 'package:fml/pages/friends_page.dart';
import 'package:fml/pages/online_page.dart';
import 'package:fml/pages/online/owner.dart';
import 'package:fml/pages/setting_page.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  try {
    await AppConfig.initialize();
    await AccountCredentials.bindDevice(
      AppConfig.instance,
      await CryptoUtil.deviceFingerprint(),
    );
    await initVersionInfo();
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('无法打开配置'),
                  const SizedBox(height: 16),
                  SelectableText(error.toString()),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => windowManager.close(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await windowManager.show();
    return;
  }
  // 设置窗口标题
  WindowOptions windowOptions = WindowOptions(
    center: true,
    title: "$kAppName v$gAppVersion ($gAppBuildNumber)",
    minimumSize: const Size(600, 600),
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  await initLogs();

  runApp(const FMLBaseApp());
}

// 软件版本
Future<void> initVersionInfo() async {
  final packageInfo = await PackageInfo.fromPlatform();

  gAppVersion = packageInfo.version;
  gAppBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;
  gAppDefaultUserAgent = 'FML/$gAppVersion';
  gAppModrinthUserAgent = 'lxdklp/FML/$gAppVersion (fml.lxdklp.top)';

  final prefs = await AppConfig.getInstance();
  await prefs.setString('version', gAppVersion);
  await prefs.setInt('build', gAppBuildNumber);
}

// 日志
Future<void> initLogs() async {
  final AppConfig prefs = await AppConfig.getInstance();
  final bool autoClearLog = (await prefs.getBool('autoClearLog')) ?? true;
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
    final prefs = await AppConfig.getInstance();
    final modeStr = (await prefs.getString('themeMode'));
    final colorInt = (await prefs.getInt('themeColor'));
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
    final prefs = await AppConfig.getInstance();
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
    final prefs = await AppConfig.getInstance();
    int colorValue =
        (((color.a * 255.0).round() & 0xFF) << 24) |
        (((color.r * 255.0).round() & 0xFF) << 16) |
        (((color.g * 255.0).round() & 0xFF) << 8) |
        ((color.b * 255.0).round() & 0xFF);
    await prefs.setInt('themeColor', colorValue);
  }

  // 使用标准字重，让系统字体匹配可用的字重。
  TextTheme _withFontWeights(TextTheme base, String? fontFamily) {
    TextStyle setW(TextStyle? s, FontWeight weight) => (s ?? const TextStyle())
        .copyWith(fontFamily: fontFamily, fontWeight: weight);
    return base.copyWith(
      bodySmall: setW(base.bodySmall, AppFontWeights.body),
      bodyMedium: setW(base.bodyMedium, AppFontWeights.body),
      bodyLarge: setW(base.bodyLarge, AppFontWeights.body),
      labelSmall: setW(base.labelSmall, AppFontWeights.label),
      labelMedium: setW(base.labelMedium, AppFontWeights.label),
      labelLarge: setW(base.labelLarge, AppFontWeights.label),
      titleSmall: setW(base.titleSmall, AppFontWeights.title),
      titleMedium: setW(base.titleMedium, AppFontWeights.title),
      titleLarge: setW(base.titleLarge, AppFontWeights.title),
      headlineSmall: setW(base.headlineSmall, AppFontWeights.headline),
      headlineMedium: setW(base.headlineMedium, AppFontWeights.headline),
      headlineLarge: setW(base.headlineLarge, AppFontWeights.headline),
      displaySmall: setW(base.displaySmall, AppFontWeights.headline),
      displayMedium: setW(base.displayMedium, AppFontWeights.headline),
      displayLarge: setW(base.displayLarge, AppFontWeights.headline),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final fontFamily = switch (defaultTargetPlatform) {
      TargetPlatform.windows => 'Microsoft YaHei', // Windows 微软雅黑
      TargetPlatform.macOS => 'PingFang SC', // macOS 苹方
      _ => null, // Linux 不指定字体
    };
    final scheme = ColorScheme.fromSeed(
      seedColor: _themeColor,
      brightness: brightness,
    );
    final baseTypography = Typography.material2021(
      platform: defaultTargetPlatform,
    );
    final raw = brightness == Brightness.dark
        ? baseTypography.white
        : baseTypography.black;
    final textTheme = _withFontWeights(raw, fontFamily);
    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
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
  bool _startupComplete = false;
  String? _startupError;

  // 使页面仅被初始化一次
  final List<Widget> _mainPages = const [
    HomePage(),
    FriendsPage(),
    OnlinePage(),
    DownloadPage(),
    SettingPage(),
  ];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) => _runStartup());
  }

  Future<void> _runStartup() async {
    try {
      final validator = GameConfigValidator(AppConfig.instance);
      final issues = await validator.scan();
      if (!mounted) return;
      await showGameConfigCheck(context, validator, issues);
      JavaService.initFuture = JavaService.init();
      await JavaService.initFuture;
      if (!mounted) return;
      if (JavaService.javaRuntimes.isEmpty) {
        final configure = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('未检测到 Java'),
            content: const Text('请在设置中选择 Java, 或安装 Java 后重新打开启动器。'),
            actions: [
              TextButton(
                onPressed: () => _launchURL(AppUrls.javaDownload),
                child: const Text('打开 Java 下载页面'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('前往设置'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('稍后配置'),
              ),
            ],
          ),
        );
        if (configure == true) _selectedIndex = 4;
      }
      if (!mounted) return;
      setState(() => _startupComplete = true);
      await _checkUpdate();
    } catch (error) {
      if (mounted) setState(() => _startupError = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_startupComplete) {
      return Scaffold(
        body: Center(
          child: _startupError == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: SelectableText('启动检查失败: $_startupError'),
                ),
        ),
      );
    }
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
                icon: Icon(Icons.people),
                label: Text('好友'),
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
          // 显示当前页面
          Expanded(
            child: LazyLoadIndexedStack(
              index: _selectedIndex,
              children: _mainPages,
            ),
          ),
        ],
      ),
    );

    mainContent = PatchPackDropTarget(
      onDrop: (path) => openPatchPack(context, archivePath: path),
      child: mainContent,
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
                onSelected: () => setState(() => _selectedIndex = 4),
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
                onSelected: () => setState(() => _selectedIndex = 4),
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

  // 打开URL
  Future<void> _launchURL(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开链接: $url')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('发生错误: $e')));
    }
  }

  // 检查更新
  Future<void> _checkUpdate() async {
    try {
      LogUtil.log('正在检查更新', level: 'INFO');
      final response = await DioClient().dio.get(
        AppUrls.latestVersionApi,
        options: Options(
          headers: {
            'User-Agent':
                '$kAppNameAbb/${Platform.operatingSystem}/$gAppVersion+$gAppBuildNumber ${kDebugMode ? 'debug' : ''}',
          },
        ),
      );
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
    await showDialog(
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

  // 显示关于对话框
  Future<void> _showAboutDialog(BuildContext context) async {
    const channel = MethodChannel(kNativeMethodChannel);
    await channel.invokeMethod('showAboutPanel');
  }
}
