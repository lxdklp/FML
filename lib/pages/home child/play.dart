import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fml/function/launcher/fabric.dart';
import 'package:fml/function/launcher/vanilla.dart';
import 'package:fml/function/launcher/neoforge.dart';

class PlayPage extends StatefulWidget {
  const PlayPage({super.key});

  @override
  _PlayPageState createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage> {
  String _GameType = '';

  // 启动类型
  Future<void> _launch() async{
    final prefs = await SharedPreferences.getInstance();
    String? _SelectedPath = prefs.getString('SelectedPath');
    String? _SelectedGame = prefs.getString('SelectedGame');
    List<String>? _GameConfig = prefs.getStringList('Config_${_SelectedPath}_$_SelectedGame');
    String? _type = _GameConfig != null && _GameConfig.length > 5 ? _GameConfig[4] : null;
    debugPrint(_GameConfig.toString());
    debugPrint(_type);
    setState(() {
      _GameType = _type ?? '';
    });
    if (_type == 'Vanilla'){
      vanillaLauncher();
    }
    if (_type == 'Fabric'){
      fabricLauncher();
    }
    if (_type == 'NeoForge'){
      neoforgeLauncher();
    }
  }

  @override
  void initState() {
    super.initState();
    _launch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('正在启动游戏'),
      ),
      body: Center(
        child: Text('类型$_GameType'),
      ),
    );
  }
}