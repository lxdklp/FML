import 'package:flutter/material.dart';
import 'package:fml/pages/home.dart';
import 'package:fml/pages/download.dart';
import 'package:fml/pages/setting.dart';

//软件版本
const version = '1.0.0';

// 应用程序入口
void main() {
  runApp(const MyApp());
}

// MyApp 类定义了应用程序的根组件
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static _MyAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>()!;

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system; // 默认跟随系统模式
  Color _themeColor = Colors.blue; // 默认主题色

  ThemeMode get themeMode => _themeMode; // 添加 themeMode getter
  Color get themeColor => _themeColor; // 添加 themeColor getter

  void changeTheme(ThemeMode themeMode) {
    setState(() {
      _themeMode = themeMode; // 更新主题模式
    });
  }

  void changeThemeColor(Color color) {
    setState(() {
      _themeColor = color; // 更新主题色
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FML', // 应用程序标题
      theme: ThemeData(
        useMaterial3: true, // 启用MD3
        colorScheme: ColorScheme.fromSeed(
          seedColor: _themeColor, // 使用MD3的颜色系统
          brightness: Brightness.light, // 亮色主题
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true, // 启用MD3
        colorScheme: ColorScheme.fromSeed(
          seedColor: _themeColor, // 使用MD3的颜色系统
          brightness: Brightness.dark, // 暗色主题
        ),
      ),
      themeMode: _themeMode, // 应用当前主题模式
      home: const MyHomePage(), // 设置主页
    );
  }
}

// MyHomePage 类定义了主页组件
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    Widget _buildPage(int _selectedIndex) {
      switch (_selectedIndex) {
        case 1:
          return const DownloadPage();
        case 2:
          return const SettingPage();
        case 0:
          return const HomePage();
        default:
            return const HomePage();
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('FML'),
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
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
            child: Center(
              child: _buildPage(_selectedIndex),
            ),
          ),
        ],
      ),
    );
  }
}
