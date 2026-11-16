import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:fml/function/config/app_config.dart';
import 'package:fml/function/config/portable_export_service.dart';

class PortableExportPage extends StatefulWidget {
  const PortableExportPage({super.key, required this.config});
  final AppConfig config;
  @override
  State<PortableExportPage> createState() => _PortableExportPageState();
}

class _PortableExportPageState extends State<PortableExportPage> {
  String? _parent;
  String? _result;
  String? _error;
  ExportProgress? _progress;
  ExportCancellation? _cancellation;
  bool _running = false;

  Future<void> _choose() async {
    final value = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择导出位置',
    );
    if (!mounted || value == null) return;
    setState(() {
      _parent = value;
      _result = null;
      _error = null;
    });
  }

  Future<void> _export() async {
    if (_parent == null || _running) return;
    final token = ExportCancellation();
    setState(() {
      _running = true;
      _error = null;
      _result = null;
      _cancellation = token;
    });
    try {
      final result = await PortableExportService(widget.config).export(
        _parent!,
        cancellation: token,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _cancellation = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.config.canExportPortable) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('转换为便携版', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        const Text(
          '将当前程序和全部 FML 配置导出为便携版。不会删除安装版以及其数据。不会复制或修改游戏文件夹，游戏目录和 Java 路径保持原样。',
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _running ? null : _choose,
            icon: const Icon(Icons.folder_open),
            label: const Text('选择导出位置'),
          ),
        ),
        if (_parent != null) ...[
          const SizedBox(height: 12),
          SelectableText(p.join(_parent!, 'FML-Portable')),
        ],
        const SizedBox(height: 24),
        if (_running) ...[
          LinearProgressIndicator(value: _progress?.fraction),
          const SizedBox(height: 12),
          Text(_progress?.stage ?? '准备导出'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _cancellation?.cancel(),
              child: const Text('取消导出'),
            ),
          ),
        ] else
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _parent == null ? null : _export,
              child: const Text('开始导出'),
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          SelectableText(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_result != null) ...[
          const SizedBox(height: 16),
          const Text('导出完成。请从导出目录中的程序启动便携版，当前安装版继续正常运行。'),
          const SizedBox(height: 8),
          SelectableText(_result!),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => OpenFilex.open(_result!),
              icon: const Icon(Icons.folder_open),
              label: const Text('打开导出文件夹'),
            ),
          ),
        ],
      ],
    );
  }
}
