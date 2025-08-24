import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  String _selectedAccount = '未知账号';
  String _selectedGame = '未知版本';
  String _selectedPath = '未知文件夹';
  String? _gameVersion;

  @override
  void initState() {
    super.initState();
    _loadGameInfo();
  }

  Future<void> _loadGameInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedAccount = prefs.getString('SelectedAccount') ?? '未选择账号';
    _selectedGame = prefs.getString('SelectedGame') ?? '未选择版本';
    _selectedPath = prefs.getString('SelectedPath') ?? '未选择文件夹';
    _gameVersion = '选择的文件夹:$_selectedPath\n选择的版本:$_selectedGame ';
    });
  }

  @override
  Widget build(BuildContext context) {
    _loadGameInfo();
    return Scaffold(
      appBar: AppBar(
      ),
      body: Center(
        child: ListView(
          children: [
            Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              title: Text('\n当前账号'),
              subtitle: Text('$_selectedAccount\n'),
              leading: const Icon(Icons.account_circle),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AccountPage()),
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
                  MaterialPageRoute(builder: (context) => const VersionPage()),
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请先选择游戏版本')),
                    );
                    return;
                  }
                  else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ManagementPage()),
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
          if (_selectedAccount == '未选择账号') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('请先选择账号')),
            );
            return;
          }
          if (_selectedGame == '未选择版本') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('请先选择游戏版本')),
            );
            return;
          }
          else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const PlayPage()),
            );
          }
        },
        child: const Icon(Icons.play_arrow),
      ),
    );
  }
}