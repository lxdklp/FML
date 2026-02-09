import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fml/function/dio_client.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fml/function/log.dart';
import 'package:fml/function/download.dart';

class ResourcepackPage extends StatefulWidget {
  const ResourcepackPage({
    required this.projectId,
    this.projectName,
    super.key,
  });

  final String projectId;
  final String? projectName;

  @override
  ResourcepackPageState createState() => ResourcepackPageState();
}

class ResourcepackPageState extends State<ResourcepackPage> {
  bool isLoading = true;
  String? error;
  List<dynamic> versionsList = [];
  List<dynamic> filteredVersionsList = [];
  Map<String, dynamic>? selectedVersion;
  Set<String> availableGameVersions = {};
  String? selectedGameVersion;
  String savePath = '';
  bool customLocation = false;

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
        final versions = response.data as List;
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

  Future<void> _applyFilters() async {
    setState(() {
      filteredVersionsList = List.from(versionsList);
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
        '应用筛选 - 游戏版本: $selectedGameVersion, 结果数量: ${filteredVersionsList.length}',
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

  // 选择保存路径
  Future<void> _selectSavePath() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      setState(() {
        savePath = selectedDirectory;
      });
    }
  }

  // 获取当前版本目录
  Future<String> _getCurrentVersionDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final pathStr = prefs.getString('Path_${prefs.getString('SelectedPath')}');
    final game = prefs.getString('SelectedGame');
    if (pathStr == null || game == null) return '';
    savePath =
        '$pathStr${Platform.pathSeparator}versions${Platform.pathSeparator}$game${Platform.pathSeparator}resourcepacks';
    return savePath;
  }

  // 下载文件
  Future<void> _downloadFile() async {
    if (selectedVersion == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择一个文件')));
      return;
    }

    final files = selectedVersion!['files'] as List?;
    if (files == null || files.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有找到可下载的文件')));
      return;
    }

    final primaryFile = files.firstWhere(
      (file) => file['primary'] == true,
      orElse: () => files.first,
    );
    final downloadUrl = primaryFile['url'];
    final fileName = primaryFile['filename'] ?? 'unknown.zip';

    if (savePath.isEmpty) {
      savePath = await _getCurrentVersionDirectory();
      if (savePath.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未选择版本目录')));
        return;
      }
    }

    if (!await Directory(savePath).exists()) {
      await Directory(savePath).create(recursive: true);
    }

    final filePath = path.join(savePath, fileName);
    _showDownloadProgressDialog(downloadUrl, filePath);
  }

  // 显示下载进度对话框
  Future<void> _showDownloadProgressDialog(String url, String savePath) async {
    final ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
    final ValueNotifier<bool> isDownloadingNotifier = ValueNotifier(true);
    final ValueNotifier<String?> errorMessageNotifier = ValueNotifier(null);
    CancelToken? cancelToken;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('正在下载'),
        content: ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (context, progress, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: isDownloadingNotifier,
              builder: (context, isDownloading, _) {
                return ValueListenableBuilder<String?>(
                  valueListenable: errorMessageNotifier,
                  builder: (context, errorMessage, _) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (errorMessage != null)
                          Text(
                            errorMessage,
                            style: const TextStyle(color: Colors.red),
                          ),
                        if (isDownloading)
                          Column(
                            children: [
                              LinearProgressIndicator(value: progress),
                              const SizedBox(height: 8),
                              Text('${(progress * 100).toStringAsFixed(1)}%'),
                              const SizedBox(height: 8),
                              Text(
                                '保存到: $savePath',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        if (!isDownloading && errorMessage == null)
                          const Text('下载完成！'),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
        actions: [
          ValueListenableBuilder(
            valueListenable: isDownloadingNotifier,
            builder: (context, isDownloading, _) {
              return isDownloading
                  ? TextButton(
                      onPressed: () {
                        cancelToken?.cancel();
                        Navigator.of(dialogContext).pop();
                      },
                      child: const Text('取消'),
                    )
                  : TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('关闭'),
                    );
            },
          ),
        ],
      ),
    );
    // 开始下载
    try {
      cancelToken = await DownloadUtils.downloadFile(
        url: url,
        savePath: savePath,
        onProgress: (currentProgress) {
          progressNotifier.value = currentProgress;
        },
        onSuccess: () {
          isDownloadingNotifier.value = false;
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('下载成功: ${path.basename(savePath)}')),
            );
            LogUtil.log('下载完成: $savePath', level: 'INFO');
          }
        },
        onError: (error) {
          errorMessageNotifier.value = '下载失败: $error';
          isDownloadingNotifier.value = false;
          if (context.mounted) {
            LogUtil.log('下载失败: $error', level: 'ERROR');
          }
        },
        onCancel: () {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('下载已取消')));
            LogUtil.log('下载已取消', level: 'INFO');
          }
        },
      );
    } catch (e) {
      errorMessageNotifier.value = '启动下载失败: $e';
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('启动下载失败: $e')));
        LogUtil.log('启动下载失败: $e', level: 'ERROR');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.projectName ?? '资源包下载')),
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
          ? const Center(child: Text('没有可用版本'))
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
                                children:
                                    (version['game_versions'] as List? ?? [])
                                        .take(5)
                                        .map<Widget>(
                                          (v) => Chip(
                                            label: Text(v.toString()),
                                            labelStyle: const TextStyle(
                                              fontSize: 10,
                                            ),
                                            padding: EdgeInsets.zero,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        )
                                        .toList(),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                          onTap: () async {
                            final currentVersion =
                                await _getCurrentVersionDirectory();
                            setState(() {
                              selectedVersion = version;
                              savePath = currentVersion;
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
                        Row(
                          children: [
                            Switch(
                              value: customLocation,
                              onChanged: (value) async {
                                if (value) {
                                  final currentVersion =
                                      await _getCurrentVersionDirectory();
                                  setState(() {
                                    customLocation = value;
                                    savePath = currentVersion;
                                  });
                                } else {
                                  setState(() {
                                    customLocation = value;
                                    savePath = '';
                                  });
                                }
                              },
                            ),
                            const Text('自定义保存位置'),
                          ],
                        ),
                        if (customLocation) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  savePath.isEmpty ? '未选择保存路径' : savePath,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TextButton(
                                onPressed: _selectSavePath,
                                child: const Text('选择路径'),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: selectedVersion != null
                                ? _downloadFile
                                : null,
                            icon: const Icon(Icons.download),
                            label: Text(
                              customLocation ? '下载到自定义位置' : '下载到当前版本目录',
                            ),
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
