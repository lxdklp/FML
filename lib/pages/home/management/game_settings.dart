import 'package:material_ui/material_ui.dart';
import 'package:fml/function/log.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:system_info2/system_info2.dart';

class GameSettingsTab extends StatefulWidget {
  final String gamePath;
  final String savesPath;
  final String screenshotsPath;
  final String logsPath;
  final String resourcepacksPath;
  final String modsPath;
  final String shaderpacksPath;
  final String schematicsPath;
  final bool hasSaves;
  final bool hasScreenshots;
  final bool hasLogs;

  const GameSettingsTab({
    super.key,
    required this.gamePath,
    required this.savesPath,
    required this.screenshotsPath,
    required this.logsPath,
    required this.resourcepacksPath,
    required this.modsPath,
    required this.shaderpacksPath,
    required this.schematicsPath,
    required this.hasSaves,
    required this.hasScreenshots,
    required this.hasLogs,
  });

  @override
  GameSettingsTabState createState() => GameSettingsTabState();
}

class GameSettingsTabState extends State<GameSettingsTab> {
  final List<String> _gameConfig = [];
  late final TextEditingController _xmxController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  bool _isFullScreen = false;
  String _width = '854';
  String _height = '480';
  String _type = '';
  int memory = 0;

  @override
  void initState() {
    super.initState();
    _xmxController = TextEditingController();
    _widthController = TextEditingController();
    _heightController = TextEditingController();
    _getMemory();
    _loadGameConfig();
  }

  @override
  void dispose() {
    _xmxController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  // 获取系统内存
  Future<void> _getMemory() async {
    int bytes = SysInfo.getTotalPhysicalMemory();
    // 内存错误修正
    if (bytes > (1024 * 1024 * 1024 * 1024) && bytes % 16384 == 0) {
      bytes = bytes ~/ 16384;
    }
    final physicalMemory = bytes ~/ (1024 * 1024);
    setState(() {
      memory = physicalMemory;
    });
  }


  // 加载游戏配置
  Future<void> _loadGameConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('SelectedPath') ?? '';
    final game = prefs.getString('SelectedGame') ?? '';
    final gameName = '_$game';
    final cfg = prefs.getStringList('Config_$path$gameName') ?? [];
    final xmx = cfg.isNotEmpty ? cfg[0] : '';
    final isFullScreen = cfg.length > 1 ? (cfg[1] == '1') : false;
    final width = cfg.length > 2 && cfg[2].isNotEmpty ? cfg[2] : _width;
    final height = cfg.length > 3 && cfg[3].isNotEmpty ? cfg[3] : _height;
    final type = cfg.length > 4 && cfg[4].isNotEmpty ? cfg[4] : _type;
    setState(() {
      _gameConfig
        ..clear()
        ..addAll(cfg);
      _xmxController.text = xmx;
      _isFullScreen = isFullScreen;
      _widthController.text = width;
      _width = width;
      _heightController.text = height;
      _height = height;
      _type = type;
    });
  }

  // 保存游戏配置
  Future<void> _saveGameConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('SelectedPath') ?? '';
    final game = prefs.getString('SelectedGame') ?? '';
    final gameName = '_$game';

    await prefs.setStringList('Config_$path$gameName', [
      _xmxController.text,
      _isFullScreen ? '1' : '0',
      _widthController.text,
      _heightController.text,
      _type,
    ]);
  }

  // 显示删除对话框
  Future<void> _showDeleteDialog() async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除版本'),
        content: Text('确定删除版本 ${widget.gamePath} 吗？文件将会全部消失'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: _deleteVersion,
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  //删除版本
  Future<void> _deleteVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString('SelectedPath') ?? '';
      final game = prefs.getString('SelectedGame') ?? '';
      final gamePath = prefs.getString('Path_$path') ?? '';
      final gameName = '_$game';
      await prefs.remove('Config_$path$gameName');
      final gamesList = prefs.getStringList('Game_$path') ?? [];
      if (gamesList.contains(game)) {
        gamesList.remove(game);
        await prefs.setStringList('Game_$path', gamesList);
      }
      final versionPath =
          '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game';
      final directory = Directory(versionPath);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
        LogUtil.log('已删除版本文件夹: $versionPath', level: 'INFO');
      } else {
        LogUtil.log('版本文件夹不存在: $versionPath', level: 'WARN');
      }
      await prefs.remove('SelectedGame');
      LogUtil.log('已清空 SelectedGame', level: 'INFO');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('版本已成功删除')));
      }
    } catch (e) {
      LogUtil.log('删除版本时出错: ${e.toString()}', level: 'ERROR');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除版本时出错: ${e.toString()}')));
      }
    } finally {
      Navigator.pop(context);
      Navigator.pop(context);
    }
  }

  // 打开文件夹
  Future<void> _launchURL(String path) async {
    try {
      String url;
      if (Platform.isWindows) {
        String fixed = path.replaceAll('\\', '/');
        if (RegExp(r'^[a-zA-Z]:').hasMatch(fixed)) {
          url = 'file:///$fixed';
        } else {
          url = 'file:///$fixed';
        }
      } else {
        url = 'file://$path';
      }
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('无法打开链接: $url')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('发生错误: $e')));
      }
      LogUtil.log(e.toString(), level: 'ERROR');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _gameConfig.isEmpty
        ? const Center(child: Text('配置出错'))
        : Stack(
            children: [
              ListView(
                padding: const EdgeInsets.only(bottom: 140),
                children: [
                  Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          title: const Text('最大堆内存 (-Xmx)'),
                          subtitle: Text(
                            '设备总内存: ${(memory / 1024).toStringAsFixed(1)} GiB, 当前分配${_xmxController.text} MiB (约 ${(double.parse(_xmxController.text) / 1024).toStringAsFixed(1)} GiB)'),
                        ),
                        Slider(
                          value: double.tryParse(_xmxController.text) ?? 1.0,
                          min: 0,
                          max: memory.toDouble(),
                          onChanged: (value) {
                            setState(() {
                              _xmxController.text = value.toStringAsFixed(0);
                            });
                          },
                        )
                      ],
                    )
                  ),
                  Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('全屏'),
                          value: _isFullScreen,
                          onChanged: (value) {
                            setState(() {
                              _isFullScreen = value;
                            });
                          },
                        ),
                        if (!_isFullScreen) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: TextField(
                              controller: _widthController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '宽度',
                                hintText: '854',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (value) =>
                                  setState(() => _width = value),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: TextField(
                              controller: _heightController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '高度',
                                hintText: '480',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (value) =>
                                  setState(() => _height = value),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: ListTile(
                      title: const Text('打开游戏文件夹'),
                      subtitle: Text(widget.gamePath),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () => _launchURL(widget.gamePath),
                    ),
                  ),
                  if (widget.hasScreenshots)
                    Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: ListTile(
                        title: const Text('打开截图文件夹'),
                        subtitle: Text(widget.screenshotsPath),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => _launchURL(widget.screenshotsPath),
                      ),
                    ),
                  if (widget.hasLogs)
                    Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: ListTile(
                        title: const Text('打开日志文件夹'),
                        subtitle: Text(widget.logsPath),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => _launchURL(widget.logsPath),
                      ),
                    ),
                ],
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FloatingActionButton(
                      heroTag: "save",
                      onPressed: () {
                        if (_widthController.text.isEmpty ||
                            _heightController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请填写所有字段')),
                          );
                          return;
                        } if (_xmxController.text == "0") {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('最大堆内存不能为 0')),
                          );
                          return;
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('配置已保存')),
                          );
                          _saveGameConfig();
                          Navigator.of(context).pop();
                        }
                      },
                      child: const Icon(Icons.save),
                    ),
                    const SizedBox(height: 16),
                    FloatingActionButton(
                      heroTag: 'delete',
                      onPressed: () {
                        _showDeleteDialog();
                      },
                      child: const Icon(Icons.delete),
                    ),
                  ],
                ),
              ),
            ],
          );
  }
}
