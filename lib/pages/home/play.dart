import 'dart:async';

import 'package:flutter/services.dart';
import 'package:fml/constants.dart';
import 'package:open_filex/open_filex.dart';
import 'package:fml/function/launcher/launch_session.dart';

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
  const PlayPage({super.key, this.session});

  final LaunchSession? session;

  @override
  PlayPageState createState() => PlayPageState();
}

class PlayPageState extends State<PlayPage> {
  late final LaunchSession _session;
  Timer? _timer;
  bool _returnAfterCancel = false;
  bool _homeScheduled = false;
  bool _logsExpanded = false;
  final ScrollController _logScrollController = ScrollController();

  bool get _canReturnHome =>
      _session.readyAt != null || _session.endedAt != null;

  void _returnHome() {
    if (mounted && _canReturnHome) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _scheduleReturnHome() {
    if (_homeScheduled) return;
    _homeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _homeScheduled = false;
      _returnHome();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    if (_returnAfterCancel && _session.endedAt != null && !_session.isActive) {
      _scheduleReturnHome();
    }
  }

  Future<void> _launch() async {
    final prefs = await AppConfig.getInstance();
    if (!mounted || _session.stopRequested) {
      _session.cancelPreparation();
      return;
    }
    final accountType = await prefs.getString('SelectedAccountType') ?? '';
    final accountName = await prefs.getString('SelectedAccountName') ?? '';
    final accountKey = accountType == '1'
        ? 'online_account_$accountName'
        : 'external_account_$accountName';
    final storedAccount = await prefs.getStringList(accountKey);
    if (!mounted || _session.stopRequested) return;
    if (AccountCredentials.needsLogin(storedAccount, accountType)) {
      if (!mounted || _session.stopRequested) {
        _session.cancelPreparation();
        return;
      }
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
      _session.cancelPreparation();
      if (mounted) _scheduleReturnHome();
      return;
    }
    String? selectedPath = (await prefs.getString('SelectedPath'));
    String? selectedGame = (await prefs.getString('SelectedGame'));
    List<String>? gameConfig = (await prefs.getStringList(
      'Config_${selectedPath}_$selectedGame',
    ));
    String? type = gameConfig != null && gameConfig.length > 4
        ? gameConfig[4]
        : null;
    if (!mounted || _session.stopRequested) return;
    LogUtil.log(gameConfig.toString(), level: 'INFO');
    LogUtil.log(type.toString(), level: 'INFO');
    _session.loader = type ?? '';
    _session.name = selectedGame ?? '';
    if (!['Vanilla', 'Fabric', 'Forge', 'NeoForge'].contains(type)) {
      _session.failPreparation('不支持的游戏类型，请重新选择版本');
      return;
    }
    final java = await configuredJavaExecutable(prefs);
    if (!mounted || _session.stopRequested) return;
    if (['Vanilla', 'Fabric', 'Forge', 'NeoForge'].contains(type)) {
      _session.prepare('正在检查 Java 版本');
      final check = await checkLaunchJava(
        metadataPath: p.join(
          (await prefs.getString('Path_$selectedPath')) ?? '',
          'versions',
          selectedGame ?? '',
          '$selectedGame.json',
        ),
        executable: java,
      );
      if (!mounted || _session.stopRequested) {
        _session.cancelPreparation();
        return;
      }
      final approved = await confirmJavaLaunch(context, check);
      if (!mounted || _session.stopRequested) {
        _session.cancelPreparation();
        return;
      }
      if (!approved) {
        _session.cancelPreparation();
        _scheduleReturnHome();
        return;
      }
    }
    final launcher = switch (type) {
      'Vanilla' => vanillaLauncher,
      'Fabric' => fabricLauncher,
      'Forge' => forgeLauncher,
      _ => neoforgeLauncher,
    };
    await launcher(
      session: _session,
      javaExecutable: java,
      onProgress: _session.prepare,
      onError: _session.failPreparation,
    );
  }

  Future<void> _loginAgain() async {
    final prefs = AppConfig.instance;
    final type = await prefs.getString('SelectedAccountType');
    final name = await prefs.getString('SelectedAccountName') ?? '';
    final account = await prefs.getStringList('external_account_$name');
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => NewAccountPage(
          initialType: type,
          serverUrl: type == '2' && account != null && account.length > 3
              ? account[2]
              : null,
          username: type == '2' && account != null && account.length > 3
              ? account[3]
              : null,
        ),
      ),
    );
  }

  Future<void> _openLogs() async {
    final path = _session.logPath;
    if (path == null) return;
    try {
      final result = await OpenFilex.open(p.dirname(path));
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开日志目录')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开日志目录')));
      }
    }
  }

  void _primaryAction() {
    if (_canReturnHome) {
      _returnHome();
      return;
    }
    _returnAfterCancel = true;
    if (!_session.stop(force: _session.stopRequested)) {
      _returnAfterCancel = false;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('未能结束游戏进程，请稍后重试')));
    }
  }

  Future<void> _copyDiagnostics() async {
    await Clipboard.setData(ClipboardData(text: _session.diagnosticText));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制诊断信息')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = _session.startupElapsed;
    final time =
        '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
    final loading =
        _session.isBusy || (_session.stopRequested && _session.endedAt == null);
    final failed = _session.hasFailure;
    final theme = Theme.of(context);
    const margin = EdgeInsets.symmetric(
      horizontal: kDefaultPadding,
      vertical: 8,
    );
    return PopScope(
      canPop: _canReturnHome,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: _canReturnHome,
          title: Text(_session.name.isEmpty ? '启动游戏' : _session.name),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 88),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  margin: margin,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      leading: loading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              failed
                                  ? Icons.error_outline
                                  : Icons.sports_esports_outlined,
                            ),
                      title: Text(_session.message),
                      subtitle: Text(
                        [
                          if (_session.loader.isNotEmpty) _session.loader,
                          '${_session.readyAt == null ? '已用时' : '启动用时'} $time',
                          if (_session.exitCode != null)
                            '退出码 ${_session.exitCode}',
                        ].join(' · '),
                      ),
                    ),
                  ),
                ),
                if (_session.state == LaunchState.starting &&
                    duration.inMinutes >= 2)
                  const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: kDefaultPadding,
                      vertical: 8,
                    ),
                    child: Text('启动耗时较长，仍在等待初始化信号。可以继续等待或查看日志。'),
                  ),
                if (failed)
                  Flexible(
                    child: Card(
                      margin: margin,
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(kDefaultPadding),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_session.diagnoses.isEmpty)
                                Text(
                                  _session.failureDetail ??
                                      '暂未识别具体原因，请查看日志中的错误信息。',
                                ),
                              for (final diagnosis in _session.diagnoses) ...[
                                Text(
                                  '${diagnosis.certain ? '' : '可能原因：'}${diagnosis.title}',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(diagnosis.advice),
                                ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  title: const Text('查看错误证据'),
                                  children: [
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxHeight: 240,
                                      ),
                                      child: SingleChildScrollView(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: SelectableText(
                                            diagnosis.evidence,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                              ],
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (_session.diagnoses.any(
                                    (d) => d.title == '账号认证失败',
                                  ))
                                    TextButton(
                                      onPressed: _loginAgain,
                                      child: const Text('重新登录'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_session.logWarning != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kDefaultPadding,
                      vertical: 8,
                    ),
                    child: Text(_session.logWarning!),
                  ),
                if (_logsExpanded)
                  Expanded(child: _buildLogs(theme, margin))
                else ...[
                  _buildLogs(theme, margin),
                  const Spacer(),
                ],
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: _canReturnHome
              ? '返回首页'
              : (_session.stopRequested ? '强制结束游戏' : '取消启动'),
          onPressed: _primaryAction,
          child: Icon(_canReturnHome ? Icons.check : Icons.clear),
        ),
      ),
    );
  }

  Widget _buildLogs(ThemeData theme, EdgeInsets margin) {
    return Card(
      margin: margin,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('游戏日志'),
            trailing: Icon(
              _logsExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            onTap: () => setState(() => _logsExpanded = !_logsExpanded),
          ),
          if (_logsExpanded)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: kDefaultPadding,
                ),
                child: SingleChildScrollView(
                  key: const ValueKey('launch-log-content'),
                  controller: _logScrollController,
                  primary: false,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SelectableText(
                      _session.recentLines.isEmpty
                          ? '尚无游戏输出'
                          : _session.recentLines.join('\n'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kDefaultPadding,
              8,
              kDefaultPadding,
              kDefaultPadding,
            ),
            child: Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _copyDiagnostics,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('复制诊断信息'),
                ),
                TextButton.icon(
                  onPressed: _session.logPath == null ? null : _openLogs,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('打开日志目录'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? LaunchSession();
    _session.addListener(_refresh);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_session.isBusy) _refresh();
    });
    if (widget.session == null) {
      // 注册会话会通知首页, 必须等当前路由完成构建后再开始.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        LaunchHistory.instance.add(_session);
        _launch().catchError(
          (Object error) => _session.failPreparation(error.toString()),
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _logScrollController.dispose();
    _session.removeListener(_refresh);
    super.dispose();
  }
}
