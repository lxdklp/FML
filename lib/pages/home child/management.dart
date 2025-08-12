import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  void initState() {
    super.initState();
    _xmxController = TextEditingController();
    _widthController = TextEditingController();
    _heightController = TextEditingController();
    _loadGameConfig();
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
    final gameName = '_$game';
    final cfg = prefs.getStringList('Config_$path$gameName') ?? [];

    // 安全读取并设置默认值
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
    ]);
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