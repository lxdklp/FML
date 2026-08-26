import 'package:material_ui/material_ui.dart';
import 'package:fml/function/log.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:desktop_drop/desktop_drop.dart';

class ShaderpackManagementTab extends StatefulWidget {
  final String shaderpacksPath;
  const ShaderpackManagementTab({super.key, required this.shaderpacksPath});

  @override
  ShaderpackManagementTabState createState() => ShaderpackManagementTabState();
}

class ShaderpackManagementTabState extends State<ShaderpackManagementTab> {
  List<FileSystemEntity> _shaderpackFiles = [];
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _loadShaderpackFiles();
  }

  // 加载光影包文件
  Future<void> _loadShaderpackFiles() async {
    if (widget.shaderpacksPath.isEmpty) return;
    final dir = Directory(widget.shaderpacksPath);
    if (await dir.exists()) {
      final files = dir.listSync().where((f) {
        final name = f.path.toLowerCase();
        return name.endsWith('.zip') || name.endsWith('.zip.fml');
      }).toList();
      setState(() {
        _shaderpackFiles = files;
      });
    }
  }

  // 判断文件是否被禁用
  bool _isFileDisabled(String path) {
    return path.toLowerCase().endsWith('.fml');
  }

  // 获取文件名
  String _getFileName(String path) {
    if (path
          .split(Platform.pathSeparator)
          .last
          .substring(
            path.split(Platform.pathSeparator).last.length - 4,
            path.split(Platform.pathSeparator).last.length,
          ) ==
        '.fml') {
      return path
          .split(Platform.pathSeparator)
          .last
          .substring(0, path.split(Platform.pathSeparator).last.length - 4);
    } else {
      return path.split(Platform.pathSeparator).last;
    }
  }

  // 切换文件启用/禁用状态
  Future<void> _toggleFileStatus(FileSystemEntity file) async {
    try {
      final path = file.path;
      final isDisabled = _isFileDisabled(path);
      String newPath;
      if (isDisabled) {
        newPath = path.substring(0, path.length - 4);
      } else {
        newPath = '$path.fml';
      }
      await File(path).rename(newPath);
      await _loadShaderpackFiles();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(isDisabled ? '已启用' : '已禁用')));
      }
    } catch (e) {
      LogUtil.log('切换文件状态时出错: ${e.toString()}', level: 'ERROR');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败: ${e.toString()}')));
      }
    }
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
        await _loadShaderpackFiles();
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

  // 分享光影
  Future<void> _shareShaderPack(FileSystemEntity file) async {
    String sharePath = file.path;
    File? tempFile;
    if (_isFileDisabled(file.path)) {
      try {
        final originalName = file.path.split(Platform.pathSeparator).last;
        final newName = originalName.substring(
          0,
          originalName.length - 4,
        );
        final tempDir = Directory.systemTemp;
        sharePath = '${tempDir.path}${Platform.pathSeparator}$newName';
        tempFile = await File(file.path).copy(sharePath);
      } catch (e) {
        LogUtil.log('准备分享光影时出错: $e', level: 'ERROR');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('准备分享光影失败: $e')));
        }
        return;
      }
    }
    try {
      final params = ShareParams(
        text: '分享光影文件: ${_getFileName(file.path)}',
        files: [XFile(sharePath)],
      );
      final result = await SharePlus.instance.share(params);
      LogUtil.log('尝试分享: $sharePath 结果: ${result.toString()}');
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
          LogUtil.log('已清理临时文件: ${tempFile.path}');
        } catch (e) {
          LogUtil.log('清理临时文件失败: $e', level: 'WARN');
        }
      }
    }
  }

  // 处理拖拽文件
  Future<void> _handleDroppedFiles(DropDoneDetails details) async {
    final files = details.files;
    int successCount = 0;
    int failCount = 0;
    List<String> failedFiles = [];
    for (final file in files) {
      final fileName = file.name.toLowerCase();
      // 只接受 .zip 文件
      if (fileName.endsWith('.zip')) {
        try {
          final sourcePath = file.path;
          final targetPath =
              '${widget.shaderpacksPath}${Platform.pathSeparator}${file.name}';
          if (await File(targetPath).exists()) {
            final overwrite = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('文件已存在'),
                content: Text('${file.name} 已存在，是否覆盖？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('跳过'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('覆盖'),
                  ),
                ],
              ),
            );
            if (overwrite != true) {
              continue;
            }
          }
          await File(sourcePath).copy(targetPath);
          successCount++;
          LogUtil.log('成功安装光影: ${file.name}', level: 'INFO');
        } catch (e) {
          failCount++;
          failedFiles.add(file.name);
          LogUtil.log('安装光影失败: ${file.name}, 错误: $e', level: 'ERROR');
        }
      } else {
        failCount++;
        failedFiles.add('${file.name} (不支持的格式)');
      }
    }
    await _loadShaderpackFiles();
    if (mounted) {
      String message;
      if (successCount > 0 && failCount == 0) {
        message = '成功安装 $successCount 个光影';
      } else if (successCount > 0 && failCount > 0) {
        message = '成功安装 $successCount 个光影，$failCount 个失败';
      } else if (failCount > 0) {
        message = '安装失败: ${failedFiles.join(', ')}';
      } else {
        message = '没有可安装的 .zip 文件';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (details) {
        setState(() {
          _isDragging = true;
        });
      },
      onDragExited: (details) {
        setState(() {
          _isDragging = false;
        });
      },
      onDragDone: (details) {
        setState(() {
          _isDragging = false;
        });
        _handleDroppedFiles(details);
      },
      child: Stack(
        children: [_buildContent(), if (_isDragging) _buildDropOverlay()],
      ),
    );
  }

  // 构建拖拽提示覆盖层
  Widget _buildDropOverlay() {
    return Container(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.file_download,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '拖放 .zip 文件到此处安装光影',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建主内容
  Widget _buildContent() {
    if (_shaderpackFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('暂无光影文件'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _launchURL(widget.shaderpacksPath),
              icon: const Icon(Icons.folder_open),
              label: const Text('打开光影文件夹'),
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
              Text('共 ${_shaderpackFiles.length} 个光影'),
              ElevatedButton.icon(
                onPressed: () => _launchURL(widget.shaderpacksPath),
                icon: const Icon(Icons.folder_open),
                label: const Text('打开文件夹'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _shaderpackFiles.length,
            itemBuilder: (context, index) {
              final file = _shaderpackFiles[index];
              final fileName = _getFileName(file.path);
              final isDisabled = _isFileDisabled(file.path);
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: Icon(isDisabled ? Icons.block : Icons.check_circle),
                  title: Text(
                    fileName,
                    style: TextStyle(
                      color: isDisabled ? Colors.grey : null,
                      decoration: isDisabled
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  subtitle: Text(isDisabled ? '已禁用' : '已启用'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.share),
                        tooltip: '分享',
                        onPressed: () => _shareShaderPack(file),
                      ),
                      IconButton(
                        icon: Icon(
                          isDisabled ? Icons.check_circle : Icons.block,
                        ),
                        tooltip: isDisabled ? '启用' : '禁用',
                        onPressed: () => _toggleFileStatus(file),
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
