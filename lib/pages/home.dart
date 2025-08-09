import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'package:flutter/material.dart';

import 'package:fml/pages/home child/account.dart';
import 'package:fml/pages/home child/version.dart';
import 'package:fml/pages/home child/management.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
      ),
      body: Center(
        child: ListView(
          children: [
            Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              title: const Text('\n 账号 \n [离线] lxdklp \n'),
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
                title: Text('\n 当前版本 \n 1.0.0 \n'),
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