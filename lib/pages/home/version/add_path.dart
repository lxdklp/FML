import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AddPathPage extends StatefulWidget {
  const AddPathPage({super.key});

  @override
  AddPathPageState createState() => AddPathPageState();
}

class AddPathPageState extends State<AddPathPage> {
  final TextEditingController _nameController = TextEditingController();
  String _dirPath = '';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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
        _dirPath = '$path${Platform.pathSeparator}.minecraft';
      });
  }

  // 创建文件夹和文件
  Future<void> _createDirectory() async {
    await _selectDirectory(); // 等待用户选择目录
    if (_dirPath.isEmpty) {
      debugPrint('未选择路径，取消创建');
      return;
    }
    final directory = Directory(_dirPath);
    if (await directory.exists()) {
      debugPrint('文件夹已存在');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件夹已存在')));
    } else {
      try {
        await directory.create(recursive: true);
        debugPrint('文件夹创建成功');
        final launcherProfilesFile = File('$_dirPath${Platform.pathSeparator}launcher_profiles.json');
        const launcherProfilesContent = '{"profiles": {"(Default)": {"name": "(Default)"}}, "selectedProfileName": "(Default)"}';
        await launcherProfilesFile.writeAsString(launcherProfilesContent);
        debugPrint('launcher_profiles.json 已创建');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件夹和配置文件已创建')));
      } catch (e) {
        debugPrint('创建文件夹失败: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建文件夹失败: $e')));
      }
    }
  }

  // 保存游戏路径
  Future<void> _saveGamePath(String path, String name) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> paths = prefs.getStringList('PathList') ?? [];
    if (paths.contains(name)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('名称$name已存在')));
      return;
    }
    paths.add(name);
    await prefs.setStringList('PathList', paths);
    await prefs.setString('Path_$name', path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('路径已添加成功')));
    await prefs.setString('SelectedPath', name);
    Navigator.pop(context);
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
                  _createDirectory();
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
            await _saveGamePath(_dirPath, _nameController.text);
          }
        },
        child: const Icon(Icons.done),
      ),
    );
  }
}
