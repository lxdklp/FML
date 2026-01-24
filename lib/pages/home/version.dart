import 'package:flutter/material.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fml/pages/home/version/add_path.dart';
import 'package:fml/pages/home/version/selected_game.dart';

class VersionPage extends StatefulWidget {
  const VersionPage({super.key});

  @override
  VersionPageState createState() => VersionPageState();
}

class VersionPageState extends State<VersionPage> {
  List<String> _pathList = [];

  @override
  void initState() {
    super.initState();
    _loadPaths();
  }

  // 读取游戏文件夹列表
  Future<void> _loadPaths() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _pathList = prefs.getStringList('PathList') ?? [];
    });
  }

  // 获取文件夹路径
  Future<String?> _getPath(String name) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('Path_$name');
  }

  // 添加文件夹后刷新
  Future<void> _addPath() async {
    await Navigator.push(context, SlidePageRoute(page: const AddPathPage()));
    _loadPaths();
  }

  // 刷新文件夹列表
  Future<void> _refreshPaths(path) async {
    Navigator.push(context, SlidePageRoute(page: SelectedGamePage(path: path)));
    await _loadPaths();
  }

  // 选择文件夹
  Future<void> _selectPath(String name) async {
    if (!mounted) return;
    _refreshPaths(name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('版本文件夹管理')),
      body: _pathList.isEmpty
          ? const Center(child: Text('暂无版本文件夹'))
          : ListView.builder(
              itemCount: _pathList.length,
              itemBuilder: (context, index) {
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    title: Text(_pathList[index]),
                    subtitle: FutureBuilder<String?>(
                      future: _getPath(_pathList[index]),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Text('加载中...');
                        } else if (snapshot.hasError) {
                          return const Text('加载失败');
                        } else {
                          return Text(snapshot.data ?? '未知路径');
                        }
                      },
                    ),
                    leading: const Icon(Icons.folder),
                    onTap: () {
                      _selectPath(_pathList[index]);
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addPath,
        child: const Icon(Icons.library_add),
      ),
    );
  }
}
