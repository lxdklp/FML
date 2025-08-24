import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fml/function/launcher/fabric.dart';
import 'package:fml/function/launcher/vanilla.dart';
import 'package:fml/function/launcher/neoforge.dart';

class PlayPage extends StatefulWidget {
  const PlayPage({super.key});

  @override
  PlayPageState createState() => PlayPageState();
}

class PlayPageState extends State<PlayPage> {
  String _GameType = '';

  // 启动类型
  Future<void> _launch() async{
    final prefs = await SharedPreferences.getInstance();
    String? SelectedPath = prefs.getString('SelectedPath');
    String? SelectedGame = prefs.getString('SelectedGame');
    List<String>? GameConfig = prefs.getStringList('Config_${SelectedPath}_$SelectedGame');
    String? type = GameConfig != null ? GameConfig[4] : null;
    debugPrint(GameConfig.toString());
    debugPrint(type);
    setState(() {
      _GameType = type ?? '';
    });
    if (type == 'Vanilla'){
      vanillaLauncher();
    }
    if (type == 'Fabric'){
      fabricLauncher();
    }
    if (type == 'NeoForge'){
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