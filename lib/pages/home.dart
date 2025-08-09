import 'package:flutter/material.dart';
import 'package:fml/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fml/pages/home child/account.dart';
import 'package:fml/pages/home child/version.dart';
import 'package:fml/pages/home child/management.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _selectedAccount = '未知账号';
  String _gameVersion = '未知版本';

  @override
  void initState() {
    super.initState();
    _loadGameInfo();
  }

  Future<void> _loadGameInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedAccount = prefs.getString('SelectedAccount') ?? '获取失败';
    });
    setState(() {
      _gameVersion = prefs.getString('GameVersion') ?? '获取失败';
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ManagementPage()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('正在启动游戏...'),
                  ),
                );
        },
        child: const Icon(Icons.play_arrow),
      ),
    );
  }
}