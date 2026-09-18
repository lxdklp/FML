import 'dart:io';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_info2/system_info2.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fml/constants.dart';
import 'package:fml/function/forge/forge_metadata.dart';
import 'package:fml/function/forge/forge_service.dart';
import 'package:fml/function/forge/forge_modpack.dart';
import 'package:fml/function/log.dart';

// 下载 forge
class DownloadForgePage extends StatefulWidget {
  const DownloadForgePage({
    super.key,
    required this.name,
    required this.version,
    required String url,
    required ForgeBuild forgeBuild,
  }) : versionUrl = url,
      build = forgeBuild,
      packUrl = null,
      source = null;

  const DownloadForgePage.modpack({
    super.key,
    required this.name,
    required String url,
    required this.source,
  }) : packUrl = url,
      version = null,
      versionUrl = null,
      build = null;

  final String name;
  final String? version;
  final String? versionUrl;
  final ForgeBuild? build;
  final String? packUrl;
  final ForgePackSource? source;

  @override
  State<DownloadForgePage> createState() => _DownloadForgePageState();
}

class _DownloadForgePageState extends State<DownloadForgePage> {
  final _steps = <String, double?>{};
  String? _error;
  bool _running = true;
  bool _complete = false;
  String? _selectedPath;
  String? _gamePath;
  bool _ownsDirectory = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _progress(String title, double? value) {
    if (mounted) setState(() => _steps[title] = value);
  }

// 通知
  Future<void> _notify(String title, String message) async {
    try {
      final notifications = FlutterLocalNotificationsPlugin();
      await notifications.initialize(
        settings: const InitializationSettings(
          macOS: DarwinInitializationSettings(),
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
          windows: WindowsInitializationSettings(
            appName: 'FML',
            appUserModelId: 'FML',
            guid: '11451419-0721-0721-0721-114514191981',
          ),
        ),
      );
      await notifications.show(
        id: 3,
        title: title,
        body: message,
        notificationDetails: const NotificationDetails(
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
      );
    } catch (e) {
      await LogUtil.log('Forge 安装通知不可用: $e', level: 'WARNING');
    }
  }

// 安装
  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _steps.clear();
    });
    try {
      if (instanceNameError(widget.name) case final String error) {
        throw FormatException(error);
      }
      final prefs = await SharedPreferences.getInstance();
      _selectedPath ??= prefs.getString('SelectedPath') ?? '';
      _gamePath ??= prefs.getString('Path_$_selectedPath') ?? '';
      if (_gamePath!.isEmpty) throw StateError('请先选择游戏文件夹');
      final folder = Directory(
        safeChild(p.join(_gamePath!, 'versions'), widget.name),
      );
      final marker = File(p.join(folder.path, '.fml-forge-install.json'));
      final request = jsonEncode({
        'minecraft': widget.version,
        'forge': widget.build?.coordinate,
        'source': widget.source?.name,
        'pack': widget.packUrl,
      });
      if (!_ownsDirectory) {
        if ((prefs.getStringList('Game_$_selectedPath') ?? []).contains(
              widget.name,
            ) ||
            (await folder.exists() &&
                (!await marker.exists() ||
                    await marker.readAsString() != request))) {
          throw StateError('已存在同名版本文件夹，请更换游戏名称');
        }
        await folder.create(recursive: true);
        await marker.writeAsString(request);
        _ownsDirectory = true;
      }
      final installer = ForgeInstaller(
        gamePath: _gamePath!,
        name: widget.name,
        onProgress: _progress,
      );
      if (widget.source != null) {
        await ForgeModpackInstaller(installer)
            .install(widget.packUrl!, widget.source!);
      } else {
        await installer.install(
          minecraft: widget.version!,
          build: widget.build!,
          versionUrl: widget.versionUrl,
        );
      }
      await installer.stage('正在保存游戏配置', () async {
        var bytes = SysInfo.getTotalPhysicalMemory();
        if (bytes > 1024 * 1024 * 1024 * 1024 && bytes % 16384 == 0) {
          bytes ~/= 16384;
        }
        final memory = (bytes ~/ (1024 * 1024 * 2)).clamp(1024, 8192);
        if (!await prefs.setStringList(
          'Config_${_selectedPath}_${widget.name}',
          ['$memory', '0', '854', '480', 'Forge', ''],
        )) {
          throw StateError('无法保存游戏配置');
        }
        final games = prefs.getStringList('Game_$_selectedPath') ?? [];
        if (!games.contains(widget.name)) games.add(widget.name);
        if (!await prefs.setStringList('Game_$_selectedPath', games)) {
          throw StateError('无法保存游戏列表');
        }
      });
      if (mounted) setState(() => _complete = true);
      try {
        if (await marker.exists()) await marker.delete();
      } catch (e) {
        await LogUtil.log('清理 Forge 安装标记失败: $e', level: 'WARNING');
      }
      await _notify('Forge 安装完成', widget.name);
    } catch (e) {
      await LogUtil.log('Forge 安装失败: $e', level: 'ERROR');
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_running,
    child: Scaffold(
      appBar: AppBar(
        title: Text(_complete ? '安装完成' : '正在安装 ${widget.name} + Forge'),
        automaticallyImplyLeading: !_running,
      ),
      body: ListView(
        padding: const EdgeInsets.all(kDefaultPadding),
        children: [
          for (final entry in _steps.entries)
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: Text(entry.key),
                    subtitle: Text(
                      _error != null && entry.key == _steps.keys.last
                          ? '失败'
                          : entry.value == 1
                          ? '完成'
                          : entry.value == null
                          ? '处理中...'
                          : '已完成 ${(entry.value! * 100).toStringAsFixed(1)}%',
                    ),
                    trailing: entry.key == _steps.keys.last && _error != null
                        ? Icon(
                            Icons.error_outline,
                            color: Theme.of(context).colorScheme.error,
                          )
                        : entry.value == 1
                        ? const Icon(Icons.check)
                        : const CircularProgressIndicator(),
                  ),
                  if (entry.value != null && entry.value != 1 && _error == null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: LinearProgressIndicator(value: entry.value),
                    ),
                ],
              ),
            ),
          if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '安装失败',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(_error!),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _running ? null : _run,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          if (_complete)
            const Card(
              child: ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text('安装完成，可以在游戏列表中选择并启动'),
              ),
            ),
        ],
      ),
      floatingActionButton: _complete
          ? FloatingActionButton(
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Icon(Icons.check),
            )
          : null,
    ),
  );
}
