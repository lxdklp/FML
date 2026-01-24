import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fml/function/log.dart';
import 'package:fml/pages/download/curseforge/type/download_modpack/download_info.dart';

class CurseforgeModpackPage extends StatefulWidget {
  const CurseforgeModpackPage({
    required this.modId,
    this.modName,
    required this.apiKey,
    super.key,
  });

  final int modId;
  final String? modName;
  final String apiKey;

  @override
  CurseforgeModpackPageState createState() => CurseforgeModpackPageState();
}

class CurseforgeModpackPageState extends State<CurseforgeModpackPage> {
  final Dio dio = Dio();
  bool _isLoading = true;
  String? _error;
  List<dynamic> _filesList = [];
  List<dynamic> _filteredFilesList = [];
  Map<String, dynamic>? _selectedFile;
  Set<String> _availableLoaders = {};
  String? _selectedLoader;
  Set<String> _availableGameVersions = {};
  String? _selectedGameVersion;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    LogUtil.log('加载CurseForge模组ID: ${widget.modId}', level: 'INFO');
    _loadAppVersion();
  }

  // 加载版本信息
  Future<void> _loadAppVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final version = prefs.getString('version') ?? "UnknownVersion";
    setState(() {
      _appVersion = version;
    });
    _fetchFiles();
  }

  // 从API获取文件信息
  Future<void> _fetchFiles() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      final response = await dio.get(
        'https://api.curseforge.com/v1/mods/${widget.modId}/files',
        queryParameters: {'pageSize': 50},
        options: Options(
          headers: {
            'x-api-key': widget.apiKey,
            'User-Agent': 'lxdklp/FML/$_appVersion (fml.lxdklp.top)',
          },
        ),
      );
      if (response.statusCode == 200) {
        final allFiles = response.data['data'] as List;
        Set<String> gameVersions = {};
        Set<String> loaders = {};
        for (var file in allFiles) {
          final fileGameVersions = file['gameVersions'] as List?;
          if (fileGameVersions != null) {
            for (var version in fileGameVersions) {
              final versionStr = version.toString();
              if (versionStr.contains('.') &&
                  !versionStr.contains('Forge') &&
                  !versionStr.contains('Fabric') &&
                  !versionStr.contains('NeoForge') &&
                  !versionStr.contains('Quilt')) {
                gameVersions.add(versionStr);
              } else if (versionStr == 'Forge' ||
                  versionStr == 'Fabric' ||
                  versionStr == 'NeoForge' ||
                  versionStr == 'Quilt') {
                loaders.add(versionStr);
              }
            }
          }
        }
        setState(() {
          _filesList = allFiles;
          _filteredFilesList = allFiles;
          _availableGameVersions = gameVersions;
          _availableLoaders = loaders;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = '请求失败: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  // 筛选文件
  Future<void> _filterFiles() async {
    setState(() {
      _filteredFilesList = _filesList.where((file) {
        final fileGameVersions = file['gameVersions'] as List?;
        if (fileGameVersions == null) return false;
        bool matchesVersion =
            _selectedGameVersion == null ||
            fileGameVersions.contains(_selectedGameVersion);
        bool matchesLoader =
            _selectedLoader == null ||
            fileGameVersions.contains(_selectedLoader);
        return matchesVersion && matchesLoader;
      }).toList();
    });
  }

  // 获取发布类型文本
  String _getReleaseTypeText(int? releaseType) {
    switch (releaseType) {
      case 1:
        return '正式版';
      case 2:
        return '测试版';
      case 3:
        return '开发版';
      default:
        return '未知';
    }
  }

  // 获取发布类型颜色
  Color _getReleaseTypeColor(int? releaseType) {
    switch (releaseType) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.modName ?? '模组文件')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error!),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _fetchFiles,
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // 筛选器
                Card(
                  margin: const EdgeInsets.all(8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '筛选',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                hint: const Text('游戏版本'),
                                value: _selectedGameVersion,
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('全部版本'),
                                  ),
                                  ..._availableGameVersions.map(
                                    (v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(v),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedGameVersion = value;
                                  });
                                  _filterFiles();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                hint: const Text('加载器'),
                                value: _selectedLoader,
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('全部'),
                                  ),
                                  ..._availableLoaders.map(
                                    (l) => DropdownMenuItem(
                                      value: l,
                                      child: Text(l),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedLoader = value;
                                  });
                                  _filterFiles();
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // 文件列表
                Expanded(
                  child: ListView.builder(
                    itemCount: _filteredFilesList.length,
                    itemBuilder: (context, index) {
                      final file = _filteredFilesList[index];
                      final isSelected = _selectedFile == file;
                      final releaseType = file['releaseType'] as int?;
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 4.0,
                        ),
                        color: isSelected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        child: ListTile(
                          leading: Icon(
                            Icons.insert_drive_file,
                            color: _getReleaseTypeColor(releaseType),
                          ),
                          title: Text(
                            file['displayName'] ?? file['fileName'] ?? '未知文件',
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_getReleaseTypeText(releaseType)} - ${file['fileName'] ?? ''}',
                              ),
                              Wrap(
                                spacing: 4,
                                children: (file['gameVersions'] as List? ?? [])
                                    .take(5)
                                    .map<Widget>(
                                      (v) => Chip(
                                        label: Text(v.toString()),
                                        labelStyle: const TextStyle(
                                          fontSize: 10,
                                        ),
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          onTap: () async {
                            setState(() {
                              _selectedFile = file;
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
                // 下载区域
                Card(
                  margin: const EdgeInsets.all(8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '下载',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        if (_selectedFile != null)
                          Text(
                            '已选择: ${_selectedFile!['displayName'] ?? _selectedFile!['fileName']}',
                          ),
                        const SizedBox(height: 8),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.download),
                            label: const Text('下载'),
                            onPressed: _selectedFile == null
                                ? null
                                : () {
                                    Navigator.push(
                                      context,
                                      SlidePageRoute(
                                        page: CurseforgeDownloadInfoPage(
                                          _selectedFile!,
                                          apiKey: widget.apiKey,
                                        ),
                                      ),
                                    );
                                  },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
