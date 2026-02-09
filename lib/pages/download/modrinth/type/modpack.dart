import 'package:flutter/material.dart';
import 'package:fml/function/dio_client.dart';

import 'package:fml/function/log.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:fml/pages/download/modrinth/type/download_modpack/donwnload_info.dart';

class ModpackPage extends StatefulWidget {
  const ModpackPage({required this.projectId, this.projectName, super.key});

  final String projectId;
  final String? projectName;

  @override
  ModpackPageState createState() => ModpackPageState();
}

class ModpackPageState extends State<ModpackPage> {
  bool isLoading = true;
  String? error;
  List<dynamic> versionsList = [];
  List<dynamic> filteredVersionsList = [];
  Map<String, dynamic>? selectedVersion;
  Set<String> availableLoaders = {'neoforge', 'fabric'};
  String? selectedLoader;
  Set<String> availableGameVersions = {};
  String? selectedGameVersion;
  String savePath = '';

  @override
  void initState() {
    super.initState();
    LogUtil.log('加载模组ID: ${widget.projectId}', level: 'INFO');
    _fetchVersions();
  }

  // 从API获取版本信息
  Future<void> _fetchVersions() async {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });
      final response = await DioClient().dio.get(
        'https://api.modrinth.com/v2/project/${widget.projectId}/version',
      );
      if (response.statusCode == 200) {
        final allVersions = response.data as List;
        final versions = allVersions.where((version) {
          final versionLoaders = version['loaders'] as List?;
          if (versionLoaders == null) return false;
          return versionLoaders.contains('neoforge') ||
              versionLoaders.contains('fabric');
        }).toList();
        Set<String> gameVersions = {};
        for (var version in versions) {
          final versionGameVersions = version['game_versions'] as List?;
          if (versionGameVersions != null) {
            for (var gameVersion in versionGameVersions) {
              gameVersions.add(gameVersion.toString());
            }
          }
        }
        setState(() {
          versionsList = versions;
          filteredVersionsList = List.from(versions);
          availableGameVersions = gameVersions;
          isLoading = false;
          if (filteredVersionsList.isNotEmpty) {
            selectedVersion = filteredVersionsList[0];
            LogUtil.log(
              '获取到${versions.length}个版本，默认选择: ${selectedVersion!['version_number']}',
              level: 'INFO',
            );
          }
          LogUtil.log('支持的加载器: neoforge, fabric', level: 'INFO');
          LogUtil.log(
            '支持的游戏版本: ${availableGameVersions.join(", ")}',
            level: 'INFO',
          );
        });
      } else {
        setState(() {
          error = '获取版本信息失败: ${response.statusCode}';
          isLoading = false;
        });
        LogUtil.log(error!, level: 'ERROR');
      }
    } catch (e) {
      setState(() {
        error = '获取版本信息出错: $e';
        isLoading = false;
      });
      LogUtil.log(error!, level: 'ERROR');
    }
  }

  // 应用当前的筛选条件
  Future<void> _applyFilters() async {
    setState(() {
      filteredVersionsList = List.from(versionsList);
      if (selectedLoader != null) {
        filteredVersionsList = filteredVersionsList.where((version) {
          final loaders = version['loaders'] as List?;
          return loaders != null && loaders.contains(selectedLoader);
        }).toList();
      }
      if (selectedGameVersion != null) {
        filteredVersionsList = filteredVersionsList.where((version) {
          final gameVersions = version['game_versions'] as List?;
          return gameVersions != null &&
              gameVersions.contains(selectedGameVersion);
        }).toList();
      }
      if (filteredVersionsList.isNotEmpty) {
        selectedVersion = filteredVersionsList[0];
      } else {
        selectedVersion = null;
      }
      LogUtil.log(
        '应用筛选 - 加载器: $selectedLoader, 游戏版本: $selectedGameVersion, 结果数量: ${filteredVersionsList.length}',
        level: 'INFO',
      );
    });
  }

  // 获取发布类型文本
  String _getVersionTypeText(String? versionType) {
    switch (versionType) {
      case 'release':
        return '正式版';
      case 'beta':
        return '测试版';
      case 'alpha':
        return '开发版';
      default:
        return '未知';
    }
  }

  // 获取发布类型颜色
  Color _getVersionTypeColor(String? versionType) {
    switch (versionType) {
      case 'release':
        return Colors.green;
      case 'beta':
        return Colors.orange;
      case 'alpha':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.projectName ?? '整合包下载')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(error!),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _fetchVersions,
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : versionsList.isEmpty
          ? const Center(child: Text('没有可用的 NeoForge 或 Fabric 版本'))
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
                                value: selectedGameVersion,
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('全部版本'),
                                  ),
                                  ...availableGameVersions.map(
                                    (v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(v),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    selectedGameVersion = value;
                                  });
                                  _applyFilters();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                hint: const Text('加载器'),
                                value: selectedLoader,
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('全部'),
                                  ),
                                  const DropdownMenuItem(
                                    value: 'neoforge',
                                    child: Text('NeoForge'),
                                  ),
                                  const DropdownMenuItem(
                                    value: 'fabric',
                                    child: Text('Fabric'),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    selectedLoader = value;
                                  });
                                  _applyFilters();
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
                    itemCount: filteredVersionsList.length,
                    itemBuilder: (context, index) {
                      final version = filteredVersionsList[index];
                      final isSelected = selectedVersion == version;
                      final versionType = version['version_type'] as String?;
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
                            color: _getVersionTypeColor(versionType),
                          ),
                          title: Text(
                            version['name'] ??
                                version['version_number'] ??
                                '未知文件',
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_getVersionTypeText(versionType)} - ${version['version_number'] ?? ''}',
                              ),
                              Wrap(
                                spacing: 4,
                                children: [
                                  ...(version['loaders'] as List? ?? [])
                                      .take(3)
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
                                      ),
                                  ...(version['game_versions'] as List? ?? [])
                                      .take(3)
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
                                      ),
                                ],
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          onTap: () {
                            setState(() {
                              selectedVersion = version;
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
                        if (selectedVersion != null)
                          Text(
                            '已选择: ${selectedVersion!['name'] ?? selectedVersion!['version_number']}',
                          ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: selectedVersion != null
                                ? () {
                                    Navigator.push(
                                      context,
                                      SlidePageRoute(
                                        page: DownloadInfo(selectedVersion!),
                                      ),
                                    );
                                  }
                                : null,
                            icon: const Icon(Icons.download),
                            label: const Text('下载整合包'),
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
