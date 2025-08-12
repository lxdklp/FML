import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_info2/system_info2.dart';

class AddPathPage extends StatefulWidget {
  const AddPathPage({super.key});

  @override
  _AddPathPageState createState() => _AddPathPageState();
}

class _AddPathPageState extends State<AddPathPage> {
  final TextEditingController _nameController = TextEditingController();
  int _mem = 1;
  String _dirPath = '';
  bool _hasGameFile = false;
  final List<String> _versions = [];

  @override
  void initState() {
    super.initState();
    _getMemory();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

    // 获取系统内存
  void _getMemory(){
    int bytes = SysInfo.getTotalPhysicalMemory();
    // 内存错误修正
    if (bytes > (1024 * 1024 * 1024 * 1024) && bytes % 16384 == 0) {
      bytes = bytes ~/ 16384;
    }
    final physicalMemory = bytes ~/ (1024 * 1024 * 1024);
    setState(() {
      _mem = physicalMemory;
    });
  }

  // 文件选择器
  Future<void> _selectDirectory() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择版本路径');
      if (!mounted) return;
      if (path == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未选择任何路径')));
        return;
      }
      setState(() {
        _dirPath = path;
      });
  }

  // 游戏版本扫描
  Future<void> _scanGameVersions(String dirPath) async {
    try {
      final versionsDir = Directory(
        dirPath.endsWith(Platform.pathSeparator)
            ? '$dirPath/versions'
            : '$dirPath/versions'
      );
      final exists = await versionsDir.exists();
      if (!mounted) return;
      if (!exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未找到版本目录')));
        setState(() {
          _hasGameFile = false;
          _versions.clear();
        });
        return;
      }

      final List<String> complete = [];
      await for (final entity in versionsDir.list(followLinks: false)){
        if (entity is! Directory) continue;
        final name = entity.path.split(Platform.pathSeparator).where((e) => e.isNotEmpty).last;
        final jar = File('${entity.path}${Platform.pathSeparator}$name.jar');
        final json = File('${entity.path}${Platform.pathSeparator}$name.json');
        final hasJar = await jar.exists();
        if (!hasJar) continue;
        final hasJson = await json.exists();
        if (!hasJson) continue;
        complete.add(name);
      }
      complete.sort();

      if (!mounted) return;
      setState(() {
        _versions
          ..clear()
          ..addAll(complete);
          _hasGameFile = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasGameFile = false;
        _versions.clear();
      });
    }
  }

  // 保存游戏路径
  Future<void> _saveGamePath(String path, String name, List<String> games) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> paths = prefs.getStringList('PathList') ?? [];
    if (paths.contains(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('名称$name已存在')));
      return;
    }
    if (!paths.contains(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已找到游戏文件: ${_versions.length} 个版本')));
      paths.add(name);
      await prefs.setStringList('PathList', paths);
      await prefs.setStringList('Game_$name', games);
      await prefs.setString('Path_$name', path);
      _createGameConfig(name, games);
      Navigator.pop(context);
    }
  }

  // 游戏配置文件创建
  Future<void> _createGameConfig(String name, List<String> games) async {
    final prefs = await SharedPreferences.getInstance();
    // 默认配置
    List<String> defaultConfig = [
      '${_mem ~/ 2}',
      '854',
      '80',
      '',
      ''
    ];
    for (final game in games) {
      final key = 'Config_${name}_$game';
      await prefs.setStringList(key, defaultConfig);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加版本路径'),
      ),
      body:  Center(
        child: ListView(
          children: [
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                decoration: InputDecoration(
                  labelText: '名称',
                  prefixIcon: const Icon(Icons.sticky_note_2),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _nameController.text = value;
                  });
                },
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: const Text('点击选择路径'),
                subtitle: Text(_dirPath.isEmpty ? '当前选择: 无' : '当前选择: $_dirPath'),
                trailing: const Icon(Icons.create_new_folder),
                onTap: () {
                  _selectDirectory();
                },
              ),
            )
          ],
        )
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async{
          if (_dirPath.isEmpty || _nameController.text.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('路径或名称不能为空')));
            return;
          } else {
            setState(() {
            });
            await _scanGameVersions(_dirPath);
            if (_hasGameFile) {
              await _saveGamePath(_dirPath, _nameController.text, _versions);
            }
          }
        },
        child: const Icon(Icons.done),
      ),
    );
  }
}