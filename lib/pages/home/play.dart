import 'package:fml/function/config/account_credentials.dart';
import 'package:fml/pages/home/account/new_account.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fml/function/config/app_config.dart';
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
    final prefs = await AppConfig.getInstance();
    if (!mounted) return;
    final accountType = await prefs.getString('SelectedAccountType') ?? '';
    final accountName = await prefs.getString('SelectedAccountName') ?? '';
    final accountKey = accountType == '1'
        ? 'online_account_$accountName'
        : 'external_account_$accountName';
    final storedAccount = await prefs.getStringList(accountKey);
    if (AccountCredentials.needsLogin(storedAccount, accountType)) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => NewAccountPage(
            initialType: accountType,
            serverUrl:
                accountType == '2' &&
                    storedAccount != null &&
                    storedAccount.length > 3
                ? storedAccount[2]
                : null,
            username:
                accountType == '2' &&
                    storedAccount != null &&
                    storedAccount.length > 3
                ? storedAccount[3]
                : null,
          ),
        ),
      );
      if (mounted) Navigator.pop(context);
      return;
    }
    String? selectedPath = (await prefs.getString('SelectedPath'));
    String? selectedGame = (await prefs.getString('SelectedGame'));
    List<String>? gameConfig = (await prefs.getStringList(
      'Config_${selectedPath}_$selectedGame',
    ));
    String account = (await prefs.getString('SelectedAccount')) ?? '';
    accountInfo = (await prefs.getStringList('Account_$account'));
    String? type = gameConfig != null && gameConfig.length > 4
        ? gameConfig[4]
        : null;
    LogUtil.log(gameConfig.toString(), level: 'INFO');
    LogUtil.log(type.toString(), level: 'INFO');
    setState(() {
      _gameType = type ?? '';
    });
    final java = await configuredJavaExecutable(prefs);
    if (['Vanilla', 'Fabric', 'Forge', 'NeoForge'].contains(type)) {
      setState(() => _message = '正在检查 Java 版本...');
      final check = await checkLaunchJava(
        metadataPath: p.join(
          (await prefs.getString('Path_$selectedPath')) ?? '',
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
          if (error.contains('重新登录'))
            TextButton(
              onPressed: () async {
                final prefs = AppConfig.instance;
                final type = await prefs.getString('SelectedAccountType');
                final name = await prefs.getString('SelectedAccountName') ?? '';
                final account = await prefs.getStringList(
                  'external_account_$name',
                );
                if (!mounted) return;
                final navigator = Navigator.of(this.context);
                navigator.pop();
                await navigator.pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => NewAccountPage(
                      initialType: type,
                      serverUrl:
                          type == '2' && account != null && account.length > 3
                          ? account[2]
                          : null,
                      username:
                          type == '2' && account != null && account.length > 3
                          ? account[3]
                          : null,
                    ),
                  ),
                );
              },
              child: const Text('重新登录'),
            ),
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
    _launch().catchError((Object error) {
      if (mounted) _handleLaunchError(error.toString());
    });
  }
}
