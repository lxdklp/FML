import 'package:flutter/material.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fml/function/log.dart';
import 'package:fml/pages/download/curseforge/type/download_modpack/loader/curseforge_fabric_modpack.dart';
import 'package:fml/pages/download/curseforge/type/download_modpack/loader/curseforge_neoforge_modpack.dart';

class CurseforgeDownloadInfoPage extends StatefulWidget {
  const CurseforgeDownloadInfoPage(
    this.file, {
    required this.apiKey,
    super.key,
  });

  final Map<String, dynamic> file;
  final String apiKey;

  @override
  CurseforgeDownloadInfoPageState createState() =>
      CurseforgeDownloadInfoPageState();
}

class CurseforgeDownloadInfoPageState
    extends State<CurseforgeDownloadInfoPage> {
  String? _downloadUrl;
  String? _fileName;
  String? _gameName;
  List<String> _versionList = [];
  List<String> _loaders = [];
  late final TextEditingController _gameNameController;

  @override
  void initState() {
    super.initState();
    _extractFileInfo();
    _loadVersionList();
    _gameNameController = TextEditingController();
    _gameNameController.text = _fileName?.replaceAll('.zip', '') ?? '';
    _gameName = _gameNameController.text;
    LogUtil.log('开始下载CurseForge整合包版本: ${widget.file}', level: 'INFO');
  }

  // 获取信息
  void _extractFileInfo() {
    setState(() {
      _downloadUrl = widget.file['downloadUrl'];
      _fileName = widget.file['fileName'];
      final gameVersions = widget.file['gameVersions'] as List?;
      if (gameVersions != null) {
        for (var v in gameVersions) {
          final vStr = v.toString().toLowerCase();
          if (vStr == 'fabric') _loaders.add('fabric');
          if (vStr == 'neoforge') _loaders.add('neoforge');
        }
      }
    });
    LogUtil.log('获取到下载地址: $_downloadUrl', level: 'INFO');
    LogUtil.log('加载器: ${_loaders.join(", ")}', level: 'INFO');
  }

  // 读取版本列表
  Future<void> _loadVersionList() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedPath = prefs.getString('SelectedPath') ?? '';
    final gameList = prefs.getStringList('Game_$selectedPath') ?? [];
    setState(() {
      _versionList = gameList;
    });
  }

  // 获取游戏版本列表
  List<String> _getGameVersions() {
    final gameVersions = widget.file['gameVersions'] as List?;
    if (gameVersions == null) return [];
    return gameVersions
        .where((v) {
          final vStr = v.toString();
          return vStr.contains('.') &&
              !vStr.toLowerCase().contains('forge') &&
              !vStr.toLowerCase().contains('fabric') &&
              !vStr.toLowerCase().contains('neoforge') &&
              !vStr.toLowerCase().contains('quilt');
        })
        .map((v) => v.toString())
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final gameVersions = _getGameVersions();
    return Scaffold(
      appBar: AppBar(title: const Text('整合包下载')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '整合包名称: ${widget.file['displayName'] ?? widget.file['fileName'] ?? '未知'}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('文件名: ${widget.file['fileName'] ?? '未知'}'),
                  const SizedBox(height: 8),
                  Text('发布日期: ${widget.file['fileDate'] ?? '未知日期'}'),
                  const SizedBox(height: 8),
                  Text('模组加载器: ${_loaders.join(", ")}'),
                  const SizedBox(height: 8),
                  Text('游戏版本: ${gameVersions.join(", ")}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _gameNameController,
                decoration: const InputDecoration(
                  labelText: '游戏名称',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() {
                  _gameName = value;
                }),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_downloadUrl == null || _downloadUrl!.isEmpty)
            Card(
              color: Colors.orange.shade100,
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  '此文件不允许第三方下载',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_gameName == null || _gameName!.isEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('请输入游戏名称')));
            return;
          }
          if (_versionList.contains(_gameName)) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('该游戏名称已存在，请换一个名称')));
            return;
          }
          if (_downloadUrl == null || _downloadUrl!.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('下载地址获取失败，此文件不允许第三方下载')),
            );
            return;
          }
          String? selectedLoader;
          if (_loaders.contains('fabric')) {
            selectedLoader = 'fabric';
          } else if (_loaders.contains('neoforge')) {
            selectedLoader = 'neoforge';
          }
          if (selectedLoader == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('此整合包不支持 Fabric 或 NeoForge 加载器')),
            );
            return;
          }
          LogUtil.log('开始下载整合包: $_fileName 类型: $selectedLoader', level: 'INFO');
          if (selectedLoader == 'fabric') {
            Navigator.of(context).push(
              SlidePageRoute(
                page: CurseforgeFabricModpackPage(
                  name: _gameName!,
                  url: _downloadUrl!,
                  apiKey: widget.apiKey,
                ),
              ),
            );
          } else if (selectedLoader == 'neoforge') {
            Navigator.of(context).push(
              SlidePageRoute(
                page: CurseforgeNeoForgeModpackPage(
                  name: _gameName!,
                  url: _downloadUrl!,
                  apiKey: widget.apiKey,
                ),
              ),
            );
          }
        },
        child: const Icon(Icons.download),
      ),
    );
  }
}
