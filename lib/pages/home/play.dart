import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:fml/function/java/java_launch_check.dart';

import 'java_version_warning.dart';

import 'package:fml/function/log.dart';
import 'package:fml/function/launcher/fabric.dart';
import 'package:fml/function/launcher/vanilla.dart';
import 'package:fml/function/launcher/neoforge.dart';
import 'package:fml/function/launcher/forge.dart';

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
    if (!mounted) return;
    String? selectedPath = prefs.getString('SelectedPath');
    String? selectedGame = prefs.getString('SelectedGame');
    List<String>? gameConfig = prefs.getStringList(
      'Config_${selectedPath}_$selectedGame',
    );
    String account = prefs.getString('SelectedAccount') ?? '';
    accountInfo = prefs.getStringList('Account_$account');
    String? type = gameConfig != null && gameConfig.length > 4
        ? gameConfig[4]
        : null;
    LogUtil.log(gameConfig.toString(), level: 'INFO');
    LogUtil.log(type.toString(), level: 'INFO');
    setState(() {
      _gameType = type ?? '';
    });
    final java = configuredJavaExecutable(prefs);
    if (['Vanilla', 'Fabric', 'Forge', 'NeoForge'].contains(type)) {
      setState(() => _message = '正在检查 Java 版本...');
      final check = await checkLaunchJava(
        metadataPath: p.join(
          prefs.getString('Path_$selectedPath') ?? '',
          'versions',
          selectedGame ?? '',
          '$selectedGame.json',
        ),
        executable: java,
      );
      if (!mounted) return;
      final approved = await confirmJavaLaunch(context, check);
      if (!mounted) return;
      if (!approved) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
    }
    if (type == 'Vanilla') {
      await vanillaLauncher(
        javaExecutable: java,
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
        javaExecutable: java,
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
    if (type == 'Forge') {
      await forgeLauncher(
        javaExecutable: java,
        onProgress: (message) {
          if (!mounted) return;
          setState(() {
            _message = message;
            if (message == '游戏启动完成') _launching = true;
          });
        },
        onError: _handleLaunchError,
      );
    }
    if (type == 'NeoForge') {
      await neoforgeLauncher(
        javaExecutable: java,
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
