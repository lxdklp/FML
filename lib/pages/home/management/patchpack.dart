import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fml/function/log.dart';
import 'package:fml/function/patchpack/patchpack_info.dart';
import 'package:fml/function/patchpack/patchpack_service.dart';
import 'package:fml/function/slide_page_route.dart';

// 打开补丁包安装页面
Future<void> openPatchPack(BuildContext context, {String? archivePath}) async {
  final prefs = await SharedPreferences.getInstance();
  final selectedPath = prefs.getString('SelectedPath');
  final game = prefs.getString('SelectedGame');
  final base = prefs.getString('Path_$selectedPath');
  if (!context.mounted) return;
  if (base == null ||
      base.isEmpty ||
      game == null ||
      game.isEmpty ||
      game == '.' ||
      game == '..' ||
      game.contains('/') ||
      game.contains('\\')) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('请先选择要安装补丁的游戏版本')));
    return;
  }
  final gamePath = p.join(base, 'versions', game);
  if (!await Directory(gamePath).exists()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('所选游戏版本的文件夹不存在')));
    }
    return;
  }
  if (!context.mounted) return;
  await Navigator.push(
    context,
    SlidePageRoute(
      page: PatchPackPage(
        gamePath: gamePath,
        gameName: game,
        archivePath: archivePath,
      ),
    ),
  );
}

// 补丁包拖放
class PatchPackDropTarget extends StatefulWidget {
  const PatchPackDropTarget({
    super.key,
    required this.child,
    required this.onDrop,
    this.enabled = true,
  });
  final Widget child;
  final Future<void> Function(String) onDrop;
  final bool enabled;

  @override
  State<PatchPackDropTarget> createState() => _PatchPackDropTargetState();
}

class _PatchPackDropTargetState extends State<PatchPackDropTarget> {
  bool _dragging = false;
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final enabled =
        widget.enabled &&
        !_opening &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    return DropTarget(
      enable: enabled,
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) async {
        setState(() => _dragging = false);
        if (!enabled) return;
        if (details.files.length != 1 ||
            p.extension(details.files.single.path).toLowerCase() != '.zip') {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('请一次拖入一个补丁包 ZIP 文件')));
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
              child: Container(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: 0.2),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.file_download,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '拖放补丁包到此处安装',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PatchPackPage extends StatefulWidget {
  const PatchPackPage({
    super.key,
    required this.gamePath,
    required this.gameName,
    this.archivePath,
  });
  final String gamePath;
  final String gameName;
  final String? archivePath;

  @override
  State<PatchPackPage> createState() => _PatchPackPageState();
}

class _PatchPackPageState extends State<PatchPackPage> {
  PatchPack? _pack;
  InstalledModpack? _installed;
  String? _fileName;
  String? _error;
  bool _reading = false;
  bool _installing = false;
  bool _finished = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    if (widget.archivePath != null) _load(widget.archivePath!);
  }

  @override
  void dispose() {
    _pack?.dispose();
    super.dispose();
  }

// 选择补丁包文件
  Future<void> _pick() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (!mounted || result == null || result.files.single.path == null) {
        return;
      }
      await _load(result.files.single.path!);
    } catch (e) {
      if (mounted) setState(() => _error = '选择文件失败：$e');
    }
  }

// 加载补丁包文件
  Future<void> _load(String path) async {
    if (_reading || _installing) return;
    final previous = _pack;
    setState(() {
      _reading = true;
      _pack = null;
      _installed = null;
      _error = null;
      _finished = false;
      _fileName = p.basename(path);
    });
    PatchPack? pack;
    try {
      await previous?.dispose();
      pack = await PatchPack.open(path);
      await pack.validateTarget(widget.gamePath);
      final installed = await readInstalledModpack(widget.gamePath);
      if (!mounted) {
        await pack.dispose();
        return;
      }
      setState(() {
        _pack = pack;
        _installed = installed;
      });
    } catch (e) {
      await pack?.dispose();
      if (mounted) setState(() => _error = '无法安装此补丁包：$e');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

// 安装补丁包
  Future<void> _install() async {
    final pack = _pack;
    if (pack == null || _installing || _finished) return;
    setState(() {
      _installing = true;
      _error = null;
      _progress = 0;
    });
    try {
      await pack.install(
        widget.gamePath,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      LogUtil.log('补丁包安装完成: ${pack.info.name} → ${widget.gamePath}');
      if (mounted) setState(() => _finished = true);
    } catch (e) {
      LogUtil.log('补丁包安装失败: $e', level: 'ERROR');
      if (mounted) {
        setState(() => _error = '安装未完成：$e\n若已开始写入, 部分文件可能已修改, 请检查实例后再重试');
      }
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

// 打开网页
  Future<void> _openWebsite(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开补丁发布页面')));
    }
  }

  Widget _card(Widget child) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final info = _pack?.info;
    final messages = info?.compatibilityMessages(_installed) ?? [];
    final uri = info?.url == null ? null : Uri.tryParse(info!.url!);
    final canOpenUrl =
        uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
    final busy = _reading || _installing;
    return PopScope(
      canPop: !_installing,
      child: Scaffold(
        appBar: AppBar(title: const Text('安装补丁包')),
        body: PatchPackDropTarget(
          enabled: !busy,
          onDrop: _load,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _card(
                ListTile(
                  leading: const Icon(Icons.videogame_asset),
                  title: Text('目标版本：${widget.gameName}'),
                  subtitle: Text(
                    [
                      widget.gamePath,
                      if (_installed?.name != null) '整合包：${_installed!.name}',
                      if (_installed?.version != null)
                        '整合包版本：${_installed!.version}',
                    ].join('\n'),
                  ),
                ),
              ),
              _card(
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fileName ?? '选择补丁包',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text('选择本地 ZIP 文件或将补丁包拖入'),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: busy ? null : _pick,
                        icon: const Icon(Icons.file_open),
                        label: Text(_fileName == null ? '选择文件' : '重新选择'),
                      ),
                      if (_reading) ...[
                        const SizedBox(height: 16),
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        const Text('正在读取并检查补丁包…'),
                      ],
                    ],
                  ),
                ),
              ),
              if (info != null) ...[
                _card(
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (info.description != null) ...[
                          const SizedBox(height: 8),
                          Text(info.description!),
                        ],
                        if (info.authors.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('作者：${info.authors.join('、')}'),
                        ],
                        if (info.modpackName != null) ...[
                          const SizedBox(height: 8),
                          Text('适用整合包：${info.modpackName}'),
                        ],
                        if (info.versionRange != null) ...[
                          const SizedBox(height: 8),
                          Text('适用版本：${info.versionRange}'),
                        ],
                        if (canOpenUrl) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => _openWebsite(uri),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('补丁发布页面'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (messages.isNotEmpty)
                  _card(
                    ListTile(
                      leading: Icon(
                        Icons.info_outline,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: const Text('兼容性提示'),
                      subtitle: Text(
                        '${messages.join('\n')}\n确认适用于当前实例后, 仍可继续安装',
                      ),
                    ),
                  ),
                _card(
                  Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.folder_copy_outlined),
                        title: const Text('安装内容'),
                        subtitle: Text(
                          '写入 ${_pack!.fileCount} 个文件；删除 ${info.delete.length} 项；重命名 ${info.rename.length} 项',
                        ),
                      ),
                      if (info.delete.isNotEmpty || info.rename.isNotEmpty)
                        ExpansionTile(
                          title: const Text('查看删除和重命名操作'),
                          children: [
                            for (final path in info.delete)
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.delete_outline),
                                title: Text(path),
                              ),
                            for (final rename in info.rename)
                              ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.drive_file_rename_outline,
                                ),
                                title: Text('${rename.from} → ${rename.to}'),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                _card(
                  const ListTile(
                    leading: Icon(Icons.warning_amber),
                    title: Text('注意'),
                    subtitle: Text(
                      '请先关闭游戏, 并仅安装可信来源的补丁\n补丁可能包含模组或脚本, 会覆盖、删除或移动实例内的文件',
                    ),
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
                    title: const Text('安装失败'),
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
                        Text('正在安装补丁… ${(_progress * 100).round()}%'),
                      ],
                    ),
                  ),
                ),
              if (_finished)
                _card(
                  const ListTile(
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('补丁包已安装'),
                    subtitle: Text('如安装的是汉化补丁, 请按补丁说明检查游戏语言设置'),
                  ),
                ),
              if (info != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _finished
                        ? FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('完成'),
                          )
                        : FilledButton.icon(
                            onPressed: busy ? null : _install,
                            icon: const Icon(Icons.install_desktop),
                            label: const Text('安装补丁'),
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
