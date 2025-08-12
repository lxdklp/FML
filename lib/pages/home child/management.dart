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

  @override
  void initState() {
    super.initState();
    _xmxController = TextEditingController();
    _loadGameConfig();
  }

  // 加载游戏配置
  Future<void> _loadGameConfig() async {
    final prefs = await SharedPreferences.getInstance();
    String path = prefs.getString('SelectedPath') ?? '';
    String game = prefs.getString('SelectedGame') ?? '';
    String gameName =  '_$game';
    List<String> cfg = prefs.getStringList('Config_$path$gameName') ?? [];
    setState(() {
        _gameConfig.clear();
        _gameConfig.addAll(cfg);
        _xmxController.text = cfg[0];
    });
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
                      decoration: InputDecoration(
                        labelText: '最大堆大小(-Xmx)',
                        hintText: '单位: GB',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    ),
                ],
              ),
      ),
    );
  }
}
