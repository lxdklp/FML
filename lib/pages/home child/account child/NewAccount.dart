import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class NewAccountPage extends StatefulWidget {
  const NewAccountPage({super.key});

  @override
  _NewAccountPageState createState() => _NewAccountPageState();
}

class _NewAccountPageState extends State<NewAccountPage> {
  bool _online = false;
  String _name = '';
  String _uuid = '';

// 保存账号
  Future<void> _saveAccountName(String name, String uuid, bool online) async {
    String isCustomUUID = '0';
    String CustomUUID = '';
    final prefs = await SharedPreferences.getInstance();
    List<String> accounts = prefs.getStringList('AccountsList') ?? [];
    if (accounts.contains(name)) {
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('账号 $name 已存在')),
      );
      return;
    }
    if (!accounts.contains(name)) {
      accounts.add(name);
      await prefs.setStringList('AccountsList', accounts);
    }
    await prefs.setStringList('Account_$name', [uuid, online.toString(), isCustomUUID, CustomUUID]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加账号'),
      ),
      body: Center(
        child: ListView(
          children: [
            Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SwitchListTile(
              title: const Text('正版模式'),
              secondary: const Icon(Icons.language),
              value: _online,
              onChanged: (bool value) {
                setState(() {
                  _online = value;
                });
              },
            ),
            ),
            if (!_online)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  decoration: const InputDecoration(
                  labelText: '离线ID \n',
                  prefixIcon: Icon(Icons.account_circle),
                  border: OutlineInputBorder(),
                ),
                onChanged: (String value) {
                  setState(() {
                    _name = value;
                  });
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_name.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('名称不能为空'),
              ),
            );
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_online
                        ? '正在添加正版账号: $_name'
                        : '正在添加离线账号: $_name'),
                  ),
                );
          // 离线UUID生成
          if (!_online) {
            _uuid = md5.convert(utf8.encode('OfflinePlayer:$_name')).toString();
          }
          _saveAccountName(_name, _uuid, _online);
          Navigator.pop(context);
        },
        child: const Icon(Icons.check),
      ),
    );
  }
}