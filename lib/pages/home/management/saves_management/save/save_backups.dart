import 'package:material_ui/material_ui.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:archive/archive.dart';
import 'package:fml/function/log.dart';

class SaveBackupsTab extends StatefulWidget {
  final String savePath;

  const SaveBackupsTab({
    super.key,
    required this.savePath,
    });

  @override
  SaveBackupsTabState createState() => SaveBackupsTabState();
}

class SaveBackupsTabState extends State<SaveBackupsTab> {
  late String _backupPath = '${widget.savePath}${Platform.pathSeparator}backups';
  List<FileSystemEntity> _backupFiles = [];

  // 加载存档文件
  Future<void> _loadBackupFiles() async {
    final dir = Directory(_backupPath);
    if (await dir.exists()) {
      final files = dir.listSync().where((f) {
        final name = f.path.toLowerCase();
        return name.endsWith('.zip');
      }).toList();
      setState(() {
        _backupFiles = files;
      });
    }
  }

  // 获取文件名
  String _getFileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  // 获取文件信息
  Future<FileStat> _getFileStat(FileSystemEntity file) async {
    return file.stat();
  }

  // 进制转换
  String _formatBytes(int bytes) {
    if (bytes <= 1024) return '${bytes.toString()} B';
    if (bytes <= 1048576) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes <= 1073741824) return '${(bytes / 1048576).toStringAsFixed(2)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }

  // 删除文件
  Future<void> _deleteFile(FileSystemEntity file) async {
    final fileName = _getFileName(file.path);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定删除 $fileName 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await file.delete();
        await _loadBackupFiles();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('文件已删除')));
        }
      } catch (e) {
        LogUtil.log('删除文件时出错: ${e.toString()}', level: 'ERROR');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('删除失败: ${e.toString()}')));
        }
      }
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

  // 分享模组
  Future<void> _shareBackup(FileSystemEntity file) async {
    String sharePath = file.path;
    final params = ShareParams(
      text: '分享模组文件: ${_getFileName(file.path)}',
      files: [XFile(sharePath)],
    );
    final result = await SharePlus.instance.share(params);
    LogUtil.log('尝试分享: $sharePath 结果: ${result.toString()}');
  }

  // 备份存档
  Future<void> _backupSave() async {
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final zipFileName = 'backup_$timestamp.zip';
      final zipFilePath = '$_backupPath${Platform.pathSeparator}$zipFileName';
      final archive = Archive();
      final saveDir = Directory(widget.savePath);
      await for (final entity in saveDir.list(recursive: true)) {
        if (entity.path.startsWith(_backupPath)) {
          continue;
        }
        if (entity is File) {
          final bytes = await entity.readAsBytes();
          final relativePath = entity.path.substring(widget.savePath.length + 1);
          final archiveFile = ArchiveFile(
            relativePath,
            bytes.length,
            bytes,
          );
          archive.addFile(archiveFile);
        }
      }
      final zipEncoder = ZipEncoder();
      final zipBytes = zipEncoder.encode(archive);
      final zipFile = File(zipFilePath);
      await zipFile.writeAsBytes(zipBytes);
      await _loadBackupFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份成功: $zipFileName')),
        );
      }
    } catch (e) {
      LogUtil.log('备份存档时出错: ${e.toString()}', level: 'ERROR');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份失败: ${e.toString()}')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadBackupFiles();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildContent(),
      floatingActionButton: FloatingActionButton(
        onPressed: _backupSave,
        child: const Icon(Icons.save),
      ),
    );
  }

  // 构建主内容
  Widget _buildContent() {
  if (_backupFiles.isEmpty) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
            const Text('暂无备份'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _launchURL(_backupPath),
              icon: const Icon(Icons.folder_open),
              label: const Text('打开 backups 文件夹'),
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
              Text('共 ${_backupFiles.length} 个备份'),
              ElevatedButton.icon(
                onPressed: () => _launchURL(_backupPath),
                icon: const Icon(Icons.folder_open),
                label: const Text('打开文件夹'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _backupFiles.length,
            itemBuilder: (context, index) {
              final file = _backupFiles[index];
              final fileName = _getFileName(file.path);
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  title: Text(fileName),
                  subtitle: FutureBuilder<FileStat> (
                    future: _getFileStat(file),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Text('加载中...');
                      } else if (snapshot.hasError) {
                        return Text('错误: ${snapshot.error}');
                      } else if (snapshot.hasData) {
                        final stat = snapshot.data!;
                        final modified = stat.modified;
                        final size = stat.size;
                        return Text('修改时间: $modified  大小: ${_formatBytes(size)}');
                      } else {
                        return const Text('无法获取文件信息');
                      }
                    },
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.share),
                        tooltip: '分享',
                        onPressed: () => _shareBackup(file),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        tooltip: '删除',
                        onPressed: () => _deleteFile(file),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
