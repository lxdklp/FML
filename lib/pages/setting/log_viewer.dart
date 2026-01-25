import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fml/function/log.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:fml/pages/setting/log_viewer/log_setting.dart';

class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  LogViewerPageState createState() => LogViewerPageState();
}

class LogViewerPageState extends State<LogViewerPage> {
  List<Map<String, dynamic>> logs = [];
  bool isLoading = true;
  String _dirPath = '';

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  // 加载日志
  Future<void> _loadLogs() async {
    setState(() {
      isLoading = true;
    });
    final loadedLogs = await LogUtil.getLogs();
    setState(() {
      logs = loadedLogs.reversed.toList();
      isLoading = false;
    });
  }

  // 清除所有日志
  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清除'),
        content: const Text('确定要清除所有日志吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await LogUtil.clearLogs();
      _loadLogs();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('日志已清除')));
      }
    }
  }

  // 文件夹选择器
  Future<void> _selectDirectory() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择版本路径',
    );
    if (!mounted) return;
    if (path == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('未选择任何路径')));
      return;
    }
    setState(() {
      _dirPath = path;
    });
  }

  // 导出全部日志
  Future<void> _exportAllLogs() async {
    await _selectDirectory();
    if (_dirPath.isEmpty) {
      return;
    }
    try {
      final directory = Directory(_dirPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final logs = await LogUtil.getLogs();
      final timestamp = DateTime.now()
          .toString()
          .replaceAll(':', '-')
          .replaceAll(' ', '_')
          .split('.')[0];
      final logFileName = 'fml_$timestamp.log';
      final logFile = File(
        '${directory.path}${Platform.pathSeparator}$logFileName',
      );
      final StringBuffer logContent = StringBuffer();
      logContent.writeln('===== FML 日志 =====');
      logContent.writeln('导出时间: ${DateTime.now()}');
      logContent.writeln('====================\n');
      for (var log in logs) {
        final timestamp = log['timestamp'] as String;
        final level = log['level'] as String;
        final caller = log['caller'] as String;
        final message = log['message'] as String;
        final dateTime = DateTime.parse(timestamp);
        final formattedTime =
            '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
            '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
        logContent.writeln('[$formattedTime] [$level] [$caller] $message');
      }
      await logFile.writeAsString(logContent.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('日志已保存至: ${logFile.path}')));
      LogUtil.log('日志已导出到: ${logFile.path}', level: 'INFO');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('日志保存失败: $e')));
      LogUtil.log('日志导出失败: $e', level: 'ERROR');
    }
  }

  // 复制单条日志到剪贴板
  Future<void> _copySingleLog(Map<String, dynamic> log) async {
    final timestamp = log['timestamp'] as String;
    final level = log['level'] as String;
    final caller = log['caller'] as String;
    final message = log['message'] as String;
    final dateTime = DateTime.parse(timestamp);
    final formattedTime =
        '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
    final logText = '[$formattedTime] [$level] [$caller] $message';
    await Clipboard.setData(ClipboardData(text: logText));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('日志已复制到剪贴板'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  // 获取日志级别对应的颜色
  Color _getLevelColor(String level) {
    switch (level.toUpperCase()) {
      case 'ERROR':
        return Colors.red;
      case 'WARNING':
        return Colors.orange;
      case 'INFO':
        return Colors.blue;
      default:
        return Colors.black;
    }
  }

  // 获取日志级别对应的图标
  IconData _getLevelIcon(String level) {
    switch (level.toUpperCase()) {
      case 'ERROR':
        return Icons.error;
      case 'WARNING':
        return Icons.warning;
      case 'INFO':
        return Icons.info;
      default:
        return Icons.article;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志查看器'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () =>
                Navigator.push(context, SlidePageRoute(page: const LogSettingPage())),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
            tooltip: '刷新',
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: logs.isEmpty ? null : _exportAllLogs,
            tooltip: '导出全部日志',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: logs.isEmpty ? null : _clearLogs,
            tooltip: '清除日志',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : logs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      '暂无日志',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                final timestamp = log['timestamp'] as String;
                final level = log['level'] as String;
                final caller = log['caller'] as String;
                final message = log['message'] as String;
                final dateTime = DateTime.parse(timestamp);
                final formattedTime =
                    '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
                    '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: ListTile(
                    leading: Icon(
                      _getLevelIcon(level),
                      color: _getLevelColor(level),
                    ),
                    title: Text(message, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(
                      '$caller\n$formattedTime',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getLevelColor(level).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        level,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _getLevelColor(level),
                        ),
                      ),
                    ),
                    onLongPress: () => _copySingleLog(log),
                  ),
                );
              },
            ),
    );
  }
}
