import 'package:flutter/material.dart';
import 'package:fml/function/log.dart';
import 'package:fml/function/slide_page_route.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:fml/pages/home/management/saves_management/save.dart';

class SavesManagementTab extends StatefulWidget {
  final String savesPath;
  const SavesManagementTab({super.key, required this.savesPath});

  @override
  SavesManagementTabState createState() => SavesManagementTabState();
}

class SavesManagementTabState extends State<SavesManagementTab> {
  List<SaveInfo> _saveFiles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSaveFiles();
  }

  // 加载存档文件夹
  Future<void> _loadSaveFiles() async {
    setState(() {
      _isLoading = true;
    });
    if (widget.savesPath.isEmpty) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final dir = Directory(widget.savesPath);
    if (await dir.exists()) {
      final List<SaveInfo> saves = [];
      final entities = dir.listSync();
      for (final entity in entities) {
        if (entity is Directory) {
          final folderName = entity.path.split(Platform.pathSeparator).last;
          final levelDatPath =
              '${entity.path}${Platform.pathSeparator}level.dat';
          final levelDatOldPath =
              '${entity.path}${Platform.pathSeparator}level.dat_old';
          // 检查是否存在 level.dat 和 level.dat_old 文件
          final levelDatExists = await File(levelDatPath).exists();
          final levelDatOldExists = await File(levelDatOldPath).exists();
          if (levelDatExists && levelDatOldExists) {
            saves.add(
              SaveInfo(
                folderName: folderName,
                folderPath: entity.path,
                levelDatPath: levelDatPath,
              ),
            );
          }
        }
      }
      setState(() {
        _saveFiles = saves;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_saveFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('暂无存档'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _launchURL(widget.savesPath),
              icon: const Icon(Icons.folder_open),
              label: const Text('打开 saves 文件夹'),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('共 ${_saveFiles.length} 个存档'),
              ElevatedButton.icon(
                onPressed: () => _launchURL(widget.savesPath),
                icon: const Icon(Icons.folder_open),
                label: const Text('打开文件夹'),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadSaveFiles,
            child: ListView.builder(
              itemCount: _saveFiles.length,
              itemBuilder: (context, index) {
                final save = _saveFiles[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.save),
                    title: Text(save.folderName),
                    subtitle: Text(save.folderPath),
                    trailing: IconButton(
                      icon: const Icon(Icons.info_outline),
                      tooltip: '查看存档信息',
                      onPressed: () => Navigator.push(
                        context,
                        SlidePageRoute(
                          page: SavePage(
                            savePath: save.folderPath,
                            saveName: save.folderName,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class SaveInfo {
  final String folderName;
  final String folderPath;
  final String levelDatPath;

  SaveInfo({
    required this.folderName,
    required this.folderPath,
    required this.levelDatPath,
  });
}
