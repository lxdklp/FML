import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'package:fml/function/config/app_config.dart';
import 'package:fml/function/forge/forge_metadata.dart';
import 'package:fml/function/mmc/mmc_install_service.dart';
import 'package:fml/function/mmc/mmc_pack.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:fml/pages/download/mmc_file_conflict_dialog.dart';

Future<void> openMmcImport(BuildContext context, {String? archivePath}) =>
    Navigator.push<void>(
      context,
      SlidePageRoute(page: MmcImportPage(archivePath: archivePath)),
    );

class MmcImportDropTarget extends StatefulWidget {
  const MmcImportDropTarget({
    super.key,
    required this.child,
    required this.onDrop,
    required this.enabled,
  });

  final Widget child;
  final Future<void> Function(String) onDrop;
  final bool enabled;

  @override
  State<MmcImportDropTarget> createState() => _MmcImportDropTargetState();
}

class _MmcImportDropTargetState extends State<MmcImportDropTarget> {
  bool _dragging = false;
  bool _opening = false;

  bool get _enabled =>
      widget.enabled &&
      !_opening &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    return DropTarget(
      enable: enabled,
      onDragEntered: (_) {
        if (_enabled) setState(() => _dragging = true);
      },
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) async {
        if (!_enabled) return;
        setState(() => _dragging = false);
        if (details.files.length != 1 ||
            p.extension(details.files.single.path).toLowerCase() != '.zip') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请一次拖入一个 MMC / Prism ZIP 文件')),
          );
          return;
        }
        setState(() => _opening = true);
        try {
          await widget.onDrop(details.files.single.path);
        } finally {
          if (mounted) setState(() => _opening = false);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_dragging && enabled)
            IgnorePointer(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: .2),
                child: const Center(child: Text('拖入 MMC / Prism ZIP 以预览整合包')),
              ),
            ),
        ],
      ),
    );
  }
}

class MmcImportPage extends StatefulWidget {
  const MmcImportPage({super.key, this.archivePath, this.config});

  final String? archivePath;
  final AppConfig? config;

  @override
  State<MmcImportPage> createState() => _MmcImportPageState();
}

class _MmcImportPageState extends State<MmcImportPage> {
  final _nameController = TextEditingController();
  late final AppConfig _config;
  StreamSubscription<Set<String>>? _configSubscription;
  MmcPack? _pack;
  MmcInstallCancellation? _cancellation;
  Map<String, String> _paths = {};
  Map<String, Set<String>> _games = {};
  String? _pathName;
  String? _archivePath;
  String? _error;
  String? _nameError;
  String _stage = '';
  double? _progress;
  bool _loadingPaths = true;
  bool _reading = false;
  bool _picking = false;
  bool _installing = false;
  bool _checkingName = false;
  int _nameCheck = 0;
  int _pathLoad = 0;

  bool get _busy => _reading || _picking || _installing;

  @override
  void initState() {
    super.initState();
    _config = widget.config ?? AppConfig.instance;
    _loadPaths();
    _configSubscription = _config.changes.listen((keys) {
      if (keys.any(
        (key) =>
            key == 'PathList' ||
            key == 'SelectedPath' ||
            key.startsWith('Path_') ||
            key.startsWith('Game_'),
      )) {
        _loadPaths();
      }
    });
    if (widget.archivePath != null) _load(widget.archivePath!);
  }

  @override
  void dispose() {
    _configSubscription?.cancel();
    _nameController.dispose();
    _cancellation?.cancel();
    // 安装仍使用暂存文件时, 由安装任务的 finally 清理.
    if (!_installing) unawaited(_pack?.dispose());
    super.dispose();
  }

  // 加载游戏目录列表
  Future<void> _loadPaths() async {
    if (_installing) return;
    final generation = ++_pathLoad;
    try {
      final data = await _config.snapshot();
      if (!mounted || generation != _pathLoad || _installing) return;
      final paths = <String, String>{};
      final games = <String, Set<String>>{};
      for (final name in (data['PathList'] as List? ?? const [])) {
        final path = data['Path_$name'];
        if (name is String && path is String && path.isNotEmpty) {
          paths[name] = path;
          games[name] = Set<String>.from(
            data['Game_$name'] as List? ?? const [],
          );
        }
      }
      final selected = _pathName ?? data['SelectedPath'];
      setState(() {
        _paths = paths;
        _games = games;
        _pathName = paths.containsKey(selected)
            ? selected as String
            : paths.keys.firstOrNull;
        _loadingPaths = false;
      });
      await _validateName();
    } catch (error) {
      if (mounted && generation == _pathLoad) {
        setState(() {
          _loadingPaths = false;
          _error = '无法读取游戏目录: $error';
        });
      }
    }
  }

  // 打开文件选择器选择整合包文件
  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (!mounted || result == null) return;
      final path = result.files.single.path;
      if (path == null) throw StateError('无法获取所选文件的路径');
      await _load(path);
    } catch (error) {
      if (mounted) setState(() => _error = '选择文件失败: $error');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  // 读取整合包信息
  Future<void> _load(String path) async {
    if (_reading || _installing) return;
    final previous = _pack;
    setState(() {
      _reading = true;
      _pack = null;
      _error = null;
      _archivePath = path;
    });
    MmcPack? pack;
    try {
      await previous?.dispose();
      if (p.extension(path).toLowerCase() != '.zip') {
        throw const FormatException('仅支持 MMC / Prism ZIP 整合包');
      }
      pack = await MmcPack.open(path);
      if (!mounted) {
        await pack.dispose();
        return;
      }
      setState(() {
        _pack = pack;
        _nameController.text = pack!.info.name;
      });
      await _validateName();
    } catch (error) {
      await pack?.dispose();
      if (mounted) setState(() => _error = '无法导入此整合包: $error');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  // 校验实例名称是否可用
  Future<bool> _validateName() async {
    final generation = ++_nameCheck;
    final name = _nameController.text;
    final pathName = _pathName;
    final root = _paths[pathName];
    var error = instanceNameError(name);
    if (error == null && root == null) error = '请先在设置中添加游戏目录';
    setState(() {
      _nameError = error;
      _checkingName = error == null;
    });
    if (error != null) return false;
    try {
      if ((_games[pathName] ?? {}).any(
            (game) => game.toLowerCase() == name.toLowerCase(),
          ) ||
          await FileSystemEntity.type(
                p.join(root!, 'versions', name),
                followLinks: false,
              ) !=
              FileSystemEntityType.notFound) {
        error = '该目录中已存在同名实例, 请使用其他名称';
      }
    } catch (exception) {
      error = '无法检查目标实例: $exception';
    }
    if (!mounted || generation != _nameCheck) return false;
    setState(() {
      _nameError = error;
      _checkingName = false;
    });
    return error == null;
  }

  // 安装整合包
  Future<void> _install() async {
    final pack = _pack;
    if (pack == null || _busy || _checkingName || _loadingPaths) return;
    // 在异步校验之前锁定按钮, 避免两个安装任务同时启动.
    setState(() {
      _installing = true;
      _error = null;
      _stage = '正在检查目标实例';
      _progress = null;
    });
    final cancellation = MmcInstallCancellation();
    _cancellation = cancellation;
    var succeeded = false;
    try {
      if (!await _validateName()) return;
      cancellation.check();
      final pathName = _pathName!;
      final gamePath = _paths[pathName]!;
      final name = _nameController.text;
      await MmcInstallService(config: _config).install(
        pack: pack,
        pathName: pathName,
        gamePath: gamePath,
        name: name,
        cancellation: cancellation,
        onFileConflict: (conflict) async {
          if (!mounted || cancellation.isCancelled) return null;
          final choice = await showMmcFileConflictDialog(context, conflict);
          if (!mounted || cancellation.isCancelled) return null;
          return choice;
        },
        onProgress: (stage, progress) {
          if (mounted) {
            setState(() {
              _stage = stage;
              _progress = progress?.clamp(0, 1).toDouble();
            });
          }
        },
      );
      succeeded = true;
    } on MmcInstallCancelled {
      if (mounted) setState(() => _error = '导入已取消, 可以重新安装或选择其他文件');
    } catch (error) {
      if (mounted) setState(() => _error = '导入失败: $error');
    } finally {
      _cancellation = null;
      if (mounted) {
        setState(() => _installing = false);
        if (!succeeded) unawaited(_loadPaths());
      } else {
        await pack.dispose();
      }
    }
    if (succeeded && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('整合包已导入')));
      Navigator.pop(context);
    }
  }

  Widget _card(Widget child) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: child,
  );

  String _size(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }

  @override
  Widget build(BuildContext context) {
    final pack = _pack;
    final info = pack?.info;
    return PopScope(
      canPop: !_installing,
      child: Scaffold(
        appBar: AppBar(title: const Text('导入整合包')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _card(
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _archivePath == null
                          ? '选择整合包'
                          : p.basename(_archivePath!),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text('支持 MultiMC / Prism Launcher 导出的实例 ZIP'),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _pick,
                      icon: const Icon(Icons.file_open),
                      label: Text(_archivePath == null ? '选择文件' : '重新选择文件'),
                    ),
                    if (_reading) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      const Text('正在读取并检查整合包'),
                    ],
                  ],
                ),
              ),
            ),
            if (_loadingPaths) _card(const LinearProgressIndicator()),
            if (!_loadingPaths && _paths.isEmpty)
              _card(
                const ListTile(
                  leading: Icon(Icons.folder_off_outlined),
                  title: Text('尚未添加游戏目录'),
                  subtitle: Text('请返回设置添加游戏目录, 再导入整合包'),
                ),
              ),
            if (info != null && pack != null) ...[
              _card(
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(info.name),
                  subtitle: Text(
                    'Minecraft ${info.minecraft}\n'
                    '加载器: ${info.loader.configName}${info.loaderVersion == null ? '' : ' ${info.loaderVersion}'}\n'
                    '文件: ${pack.fileCount} 个, 解压后 ${_size(pack.expandedSize)}',
                  ),
                ),
              ),
              _card(
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_paths.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          initialValue: _pathName,
                          key: ValueKey(_pathName),
                          decoration: const InputDecoration(
                            labelText: '目标游戏目录',
                          ),
                          isExpanded: true,
                          items: [
                            for (final entry in _paths.entries)
                              DropdownMenuItem(
                                value: entry.key,
                                child: Text(
                                  '${entry.key}: ${entry.value}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _busy
                              ? null
                              : (value) {
                                  setState(() => _pathName = value);
                                  _validateName();
                                },
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        controller: _nameController,
                        enabled: !_busy,
                        decoration: InputDecoration(
                          labelText: '实例名称',
                          errorText: _nameError,
                          helperText: _checkingName
                              ? '正在检查名称'
                              : '将创建独立实例, 同名实例不会被覆盖',
                        ),
                        onChanged: (_) => _validateName(),
                      ),
                      if (_paths[_pathName] != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          '安装位置: ${p.join(_paths[_pathName]!, 'versions', _nameController.text)}',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              _card(
                ListTile(
                  leading: const Icon(Icons.public),
                  title: Text('存档: ${info.worlds.length} 个'),
                  subtitle: info.worlds.isEmpty
                      ? const Text('整合包未包含存档')
                      : Text(info.worlds.join('\n')),
                ),
              ),
              if (info.warnings.isNotEmpty)
                _card(
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('导入提示'),
                    subtitle: Text(info.warnings.join('\n')),
                  ),
                ),
            ],
            if (_error != null)
              _card(
                ListTile(
                  leading: Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: const Text('导入未完成'),
                  subtitle: SelectableText(_error!),
                ),
              ),
            if (_installing)
              _card(
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: _progress),
                      const SizedBox(height: 8),
                      Text(
                        _cancellation?.isCancelled == true
                            ? '正在取消, 等待当前阶段安全结束'
                            : _stage,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _cancellation?.isCancelled == true
                            ? null
                            : () {
                                _cancellation?.cancel();
                                setState(() {});
                              },
                        child: const Text('取消导入'),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 12,
                alignment: WrapAlignment.end,
                children: [
                  if (pack == null && _archivePath != null && !_busy)
                    TextButton(
                      onPressed: () => _load(_archivePath!),
                      child: const Text('重新读取'),
                    ),
                  if (pack != null)
                    FilledButton.icon(
                      onPressed:
                          _busy ||
                              _loadingPaths ||
                              _checkingName ||
                              _nameError != null ||
                              _paths.isEmpty
                          ? null
                          : _install,
                      icon: const Icon(Icons.install_desktop),
                      label: Text(_error == null ? '导入整合包' : '重试导入'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
