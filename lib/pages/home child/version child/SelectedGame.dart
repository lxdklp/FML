import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SelectedGamePage extends StatefulWidget {
  final String path;
  const SelectedGamePage({super.key, required this.path});

  @override
  _SelectedGamePageState createState() => _SelectedGamePageState();
}

class _SelectedGamePageState extends State<SelectedGamePage> {
  List<String> _gameList = [];

  @override
  void initState() {
    super.initState();
    _loadGames();
  }

  // 读取游戏列表
  Future<void> _loadGames() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _gameList = prefs.getStringList('Path_${widget.path}') ?? [];
    });
  }

  // 选择版本
  Future<void> _selectGame(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('SelectedPath', widget.path);
    await prefs.setString('SelectedGame', name);
    if (!mounted) return;
    Navigator.pop(context);
    Navigator.pop(context);
  }

  // 删除路径
  Future<void> _deletePath() async {
    final prefs = await SharedPreferences.getInstance();
    final pathList = prefs.getStringList('PathList') ?? [];
    pathList.remove(widget.path);
    await prefs.setStringList('PathList', pathList);
    await prefs.remove('Path_${widget.path}');
    if (widget.path == prefs.getString('SelectedPath')) {
      await prefs.remove('SelectedPath');
      await prefs.remove('SelectedGame');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除文件夹: ${widget.path}')),
    );
    Navigator.pop(context);
    Navigator.pop(context);
    Navigator.pop(context);
  }

  // 删除提示框
    void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除路径'),
        content: Text('确定删除路径 ${widget.path} ？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: _deletePath,
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('游戏选择'),
      ),
      body: _gameList.isEmpty
          ? const Center(child: Text('游戏列表出错'))
          : ListView.builder(
              itemCount: _gameList.length,
              itemBuilder: (context, index) {
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    title: Text(_gameList[index]),
                    leading: const Icon(Icons.bookmark),
                    onTap: () {
                      _selectGame(_gameList[index]);
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showDeleteDialog();
        },
        child: const Icon(Icons.delete),
      ),
    );
  }
}