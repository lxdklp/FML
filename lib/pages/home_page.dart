import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:fml/function/config/app_config.dart';

import 'package:fml/pages/home/account.dart';
import 'package:fml/pages/home/version.dart';
import 'package:fml/pages/home/management.dart';
import 'package:fml/pages/home/play.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  String _selectedAccountName = '未知账号';
  String _selectedAccountType = '3';
  String _selectedGame = '未知版本';
  String _selectedPath = '未知文件夹';
  String? _gameVersion;
  StreamSubscription<Set<String>>? _configSubscription;

  @override
  void initState() {
    super.initState();
    _loadGameInfo();
    _configSubscription = AppConfig.instance.changes.listen((keys) {
      if (keys.any(
        (key) => const {
          'SelectedPath',
          'SelectedGame',
          'SelectedAccountName',
          'SelectedAccountType',
        }.contains(key),
      )) {
        _loadGameInfo();
      }
    });
  }

  @override
  void dispose() {
    _configSubscription?.cancel();
    super.dispose();
  }

  // 读取游戏信息
  Future<void> _loadGameInfo() async {
    final prefs = await AppConfig.getInstance();

    _selectedAccountName =
        (await prefs.getString('SelectedAccountName')) ?? '未选择账号';
    _selectedAccountType =
        (await prefs.getString('SelectedAccountType')) ?? '4';
    _selectedGame = (await prefs.getString('SelectedGame')) ?? '未选择版本';
    _selectedPath = (await prefs.getString('SelectedPath')) ?? '未选择文件夹';
    _gameVersion = '选择的文件夹:$_selectedPath\n选择的版本:$_selectedGame ';
    if (!mounted) return;
    setState(() {});
  }

  // 登录模式
  String _getLoginModeText(String loginMode) {
    switch (loginMode) {
      case '0':
        return '离线登录';
      case '1':
        return '正版登录';
      case '2':
        return '外置登录';
      case '3':
        return '未知类型';
      case '4':
        return '未选择账号';
      default:
        return '未知类型';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: ListView(
          children: [
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: Text('\n当前账号'),
                subtitle: Text(
                  '[${_getLoginModeText(_selectedAccountType)}]$_selectedAccountName\n',
                ),
                leading: const Icon(Icons.account_circle),
                onTap: () {
                  Navigator.push(
                    context,
                    SlidePageRoute(page: const AccountPage()),
                  );
                },
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: Text('\n当前版本'),
                subtitle: Text('$_gameVersion\n'),
                leading: const Icon(Icons.view_list),
                onTap: () {
                  Navigator.push(
                    context,
                    SlidePageRoute(page: const VersionPage()),
                  );
                },
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: Text('\n 版本设置 \n'),
                leading: const Icon(Icons.tune),
                onTap: () {
                  if (_selectedGame == '未选择版本') {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('请先选择游戏版本')));
                    return;
                  } else {
                    Navigator.push(
                      context,
                      SlidePageRoute(page: const ManagementPage()),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_selectedAccountName == '未选择账号') {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('请先选择账号')));
            return;
          }
          if (_selectedGame == '未选择版本') {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('请先选择游戏版本')));
            return;
          } else {
            Navigator.push(context, SlidePageRoute(page: const PlayPage()));
          }
        },
        child: const Icon(Icons.play_arrow),
      ),
    );
  }
}
