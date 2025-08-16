import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

class ManagementPage extends StatefulWidget {
  const ManagementPage({super.key});

  @override
  _ManagementPageState createState() => _ManagementPageState();
}

class _ManagementPageState extends State<ManagementPage> {
  final List<String> _gameConfig = [];
  late final TextEditingController _xmxController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  bool _isFullScreen = false;
  String _width = '854';
  String _height = '480';
  String _gamePath = '';
  bool _saves = false;
  bool _resourcepacks = false;
  bool _mods = false;
  bool _shaderpacks = false;
  bool _schematics = false;
  String _savesPath = '';
  String _resourcepacksPath = '';
  String _modsPath = '';
  String _shaderpacksPath = '';
  String _schematicsPath = '';

  @override
  void initState() {
    super.initState();
    _xmxController = TextEditingController();
    _widthController = TextEditingController();
    _heightController = TextEditingController();
    _loadGameConfig();
    _checkDirectory();
  }

  @override
  void dispose() {
    _xmxController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  // 加载游戏配置
  Future<void> _loadGameConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('SelectedPath') ?? '';
    final game = prefs.getString('SelectedGame') ?? '';
    final gamePath = prefs.getString('Path_$path') ?? '';
    final fullPath = '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game';
    final gameName = '_$game';
    final cfg = prefs.getStringList('Config_$path$gameName') ?? [];
    final xmx = cfg.isNotEmpty ? cfg[0] : '';
    final isFullScreen = cfg.length > 1 ? (cfg[1] == '1') : false;
    final width = cfg.length > 2 && cfg[2].isNotEmpty ? cfg[2] : _width;
    final height = cfg.length > 3 && cfg[3].isNotEmpty ? cfg[3] : _height;
    setState(() {
      _gameConfig
        ..clear()
        ..addAll(cfg);
      _xmxController.text = xmx;
      _isFullScreen = isFullScreen;
      _widthController.text = width;
      _width = width;
      _heightController.text = height;
      _height = height;
      _gamePath = fullPath;
    });
  }

  // 保存游戏配置
  Future<void> _saveGameConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('SelectedPath') ?? '';
    final game = prefs.getString('SelectedGame') ?? '';
    final gameName = '_$game';

    await prefs.setStringList('Config_$path$gameName', [
      _xmxController.text,
      _isFullScreen ? '1' : '0',
      _widthController.text,
      _heightController.text,
      'Fabric',
    ]);
  }

  // 文件夹检查功能
  Future<bool> checkDirectoryFuture(String path) async {
    final dir = Directory(path);
    return await dir.exists();
  }

  //检查文件夹
  Future<void> _checkDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedPath = prefs.getString('SelectedPath') ?? '';
    final game = prefs.getString('SelectedGame') ?? '';
    final gamePath = prefs.getString('Path_$selectedPath') ?? '';
    final path = '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game';
    // 检查存档文件夹
    final savesExists = await checkDirectoryFuture('$path${Platform.pathSeparator}saves');
    if (savesExists) {
      setState(() {
        _saves = true;
        _savesPath = '$path${Platform.pathSeparator}saves';
      });
    }
    // 检查资源包文件夹
    final resourcepacksExists = await checkDirectoryFuture('$path${Platform.pathSeparator}resourcepacks');
    if (resourcepacksExists) {
      setState(() {
        _resourcepacks = true;
        _resourcepacksPath = '$path${Platform.pathSeparator}resourcepacks';
      });
    }
    // 检查模组文件夹
    final modsExists = await checkDirectoryFuture('$path${Platform.pathSeparator}mods');
    if (modsExists) {
      setState(() {
        _mods = true;
        _modsPath = '$path${Platform.pathSeparator}mods';
      });
    }final shaderpacksExists = await checkDirectoryFuture('$path${Platform.pathSeparator}shaderpacks');
    if (shaderpacksExists) {
      setState(() {
        _shaderpacks = true;
        _shaderpacksPath = '$path${Platform.pathSeparator}shaderpacks';
      });
    }
    final schematicsExists = await checkDirectoryFuture('$path${Platform.pathSeparator}schematics');
    if (schematicsExists) {
      setState(() {
        _schematics = true;
        _schematicsPath = '$path${Platform.pathSeparator}schematics';
      });
    }
  }

    // 打开文件夹
  Future<void> _launchURL(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开链接: $url')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发生错误: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('版本设置'),
      ),
      body: Center(
        child: _gameConfig.isEmpty
            ? const Text('配置出错')
            : ListView(
                children: [
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      controller: _xmxController,
                      decoration: const InputDecoration(
                        labelText: '最大堆大小(-Xmx)',
                        hintText: '单位: GB',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('全屏'),
                          value: _isFullScreen,
                          onChanged: (value) {
                            setState(() {
                              _isFullScreen = value;
                            });
                          },
                        ),
                        if (!_isFullScreen) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: TextField(
                              controller: _widthController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '宽度',
                                hintText: '854',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (value) => setState(() => _width = value),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: TextField(
                              controller: _heightController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '高度',
                                hintText: '480',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (value) => setState(() => _height = value),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        title: const Text('打开游戏文件夹'),
                        subtitle: Text(_gamePath),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => _launchURL('file://$_gamePath'),
                      ),
                    ),
                  if (_resourcepacks)
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        title: const Text('打开存档文件夹'),
                        subtitle: Text(_savesPath),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => _launchURL('file://$_savesPath'),
                      ),
                    ),if (_resourcepacks)
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        title: const Text('打开资源包文件夹'),
                        subtitle: Text(_resourcepacksPath),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => _launchURL('file://$_resourcepacksPath'),
                      ),
                    ),if (_mods)
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        title: const Text('打开模组文件夹'),
                        subtitle: Text(_modsPath),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => _launchURL('file://$_modsPath'),
                      ),
                    ),if (_shaderpacks)
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        title: const Text('打开光影文件夹'),
                        subtitle: Text(_shaderpacksPath),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => _launchURL('file://$_shaderpacksPath'),
                      ),
                    ),if (_schematics)
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        title: const Text('打开原理图文件夹'),
                        subtitle: Text(_schematicsPath),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => _launchURL('file://$_schematicsPath'),
                      ),
                    ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_xmxController.text.isEmpty || _widthController.text.isEmpty || _heightController.text.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('请填写所有字段')),
            );
            return;
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('配置已保存')),
            );
            _saveGameConfig();
            Navigator.of(context).pop();
          }
        },
        child: const Icon(Icons.save),
      ),
    );
  }
}