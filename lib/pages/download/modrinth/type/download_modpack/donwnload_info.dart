import 'package:flutter/material.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fml/function/log.dart';
import 'package:fml/pages/download/modrinth/type/download_modpack/loader/modrinth_fabric_modpack.dart';
import 'package:fml/pages/download/modrinth/type/download_modpack/loader/modrinth_neoforge_modpack.dart';

class DownloadInfo extends StatefulWidget {
  const DownloadInfo(this.version, {super.key});

  final Map<String, dynamic> version;

  @override
  DownloadInfoState createState() => DownloadInfoState();
}

class DownloadInfoState extends State<DownloadInfo> {
  String? _downloadUrl;
  String? _fileName;
  String? _gameName;
  List<String> _versionList = [];
  late final TextEditingController _gameNameController;

  @override
  void initState() {
    super.initState();
    _extractFileInfo();
    _loadVersionList();
    _gameNameController = TextEditingController();
    _gameNameController.text = _fileName ?? '';
    _gameName = _gameNameController.text;
    LogUtil.log(
      '开始下载模组包版本: ${widget.version['version_number']}',
      level: 'INFO',
    );
  }

  // 获取信息
  void _extractFileInfo() {
    final files = widget.version['files'] as List?;
    if (files != null && files.isNotEmpty) {
      final primaryFile = files.firstWhere(
        (file) => file['primary'] == true,
        orElse: () => files.first,
      );
      setState(() {
        _downloadUrl = primaryFile['url'];
        _fileName = primaryFile['filename'];
      });
      LogUtil.log('获取到下载地址: $_downloadUrl', level: 'INFO');
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('模组包下载')),
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
                    '模组包名称: $_fileName',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('版本: ${widget.version['version_number'] ?? '未知版本'}'),
                  const SizedBox(height: 8),
                  Text('发布日期: ${widget.version['date_published'] ?? '未知日期'}'),
                  const SizedBox(height: 8),
                  Text(
                    '模组加载器: ${widget.version['loaders']?.join(", ") ?? '未知加载器'}',
                  ),
                  if (widget.version['changelog'] != null &&
                      widget.version['changelog'].toString().isNotEmpty)
                    const SizedBox(height: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '更新日志:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                        child: Text(widget.version['changelog'].toString()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: TextField(
              controller: _gameNameController,
              decoration: InputDecoration(
                labelText: '游戏名称',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() {
                _gameName = value;
              }),
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
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('下载地址获取失败')));
            return;
          }
          if (widget.version['loaders']?.join(", ") == 'fabric') {
            LogUtil.log(
              '开始下载模组包: $_fileName 类型: ${widget.version['loaders']}',
              level: 'INFO',
            );
            Navigator.of(context).push(
              SlidePageRoute(
                page: FabricModpackPage(
                  name: _gameName!,
                  url: _downloadUrl ?? '',
                ),
              ),
            );
          }
          if (widget.version['loaders']?.join(", ") == 'neoforge') {
            LogUtil.log(
              '开始下载模组包: $_fileName 类型: ${widget.version['loaders']}',
              level: 'INFO',
            );
            Navigator.of(context).push(
              SlidePageRoute(
                page: NeoForgeModpackPage(
                  name: _gameName!,
                  url: _downloadUrl ?? '',
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
