import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fml/function/log.dart';
import 'package:fml/function/launcher/fabric.dart';
import 'package:fml/function/launcher/vanilla.dart';
import 'package:fml/function/launcher/neoforge.dart';

class PlayPage extends StatefulWidget {
  const PlayPage({super.key});

  @override
  PlayPageState createState() => PlayPageState();
}

class PlayPageState extends State<PlayPage> {
  String _gameType = '';
  List<String>? accountInfo;
  String _message = '正在启动游戏...';
  bool _launching = false;

  Future<void> _launch() async {
    final prefs = await SharedPreferences.getInstance();
    String? selectedPath = prefs.getString('SelectedPath');
    String? selectedGame = prefs.getString('SelectedGame');
    List<String>? gameConfig = prefs.getStringList('Config_${selectedPath}_$selectedGame');
    String account = prefs.getString('SelectedAccount') ?? '';
    accountInfo = prefs.getStringList('Account_$account');
    String? type = gameConfig != null ? gameConfig[4] : null;
    LogUtil.log(gameConfig.toString(), level: 'INFO');
    LogUtil.log(type.toString(), level: 'INFO');
    setState(() {
      _gameType = type ?? '';
    });
    if (type == 'Vanilla'){
      await vanillaLauncher(
      onProgress: (String message) {
          setState(() {
            _message = message;
          });
          if (message == '游戏启动完成') {
            setState(() {
              _launching = true;
            });
          }
        },
        onError: _handleLaunchError,
      );
    }
    if (type == 'Fabric') {
      await fabricLauncher(
        onProgress: (String message) {
          setState(() {
            _message = message;
          });
          if (message == '游戏启动完成') {
            setState(() {
              _launching = true;
            });
          }
        },
        onError: _handleLaunchError,
      );
    }
    if (type == 'NeoForge') {
      await neoforgeLauncher(
        onProgress: (String message) {
          setState(() {
            _message = message;
          });
          if (message == '游戏启动完成') {
            setState(() {
              _launching = true;
            });
          }
        },
        onError: _handleLaunchError,
      );
    }
  }

  // 启动失败时弹窗提示并终止启动流程
  void _handleLaunchError(String error) {
    LogUtil.log('启动失败: $error', level: 'ERROR');
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('启动失败'),
        content: Text(error),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('正在启动$_gameType')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _message,
            style: const TextStyle(fontSize: 18),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      floatingActionButton: _launching
      ? FloatingActionButton(
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Icon(Icons.check),
          )
        : null,
    );
  }

  @override
  void initState() {
    super.initState();
    _launch();
  }
}