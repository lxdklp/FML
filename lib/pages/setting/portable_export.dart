import 'package:fml/constants.dart';
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

  Widget _settingsCard(BuildContext context, Widget child) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.config.canExportPortable) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: kDefaultPadding),
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: kDefaultPadding / 2,
            top: kDefaultPadding,
            bottom: kDefaultPadding,
          ),
          child: Text('转换为便携版', style: theme.textTheme.headlineMedium),
        ),
        _settingsCard(
          context,
          const ListTile(
            title: Text('导出程序和配置'),
            subtitle: Text('不会删除安装版以及其数据。不会复制或修改游戏文件夹，游戏目录和 Java 路径保持原样。'),
          ),
        ),
        _settingsCard(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('导出位置'),
                subtitle: Text(
                  _parent == null
                      ? '选择用于保存便携版的文件夹'
                      : p.join(_parent!, 'FML-Portable'),
                ),
                trailing: const Icon(Icons.chevron_right),
                enabled: !_running,
                onTap: _running ? null : _choose,
              ),
              Padding(
                padding: const EdgeInsets.all(kDefaultPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_running) ...[
                      LinearProgressIndicator(value: _progress?.fraction),
                      const SizedBox(height: kDefaultPadding / 2),
                      Text(
                        _progress?.stage ?? '准备导出',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: kDefaultPadding / 2),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: _running
                          ? TextButton(
                              onPressed: () => _cancellation?.cancel(),
                              child: const Text('取消导出'),
                            )
                          : FilledButton(
                              onPressed: _parent == null ? null : _export,
                              child: const Text('开始导出'),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          _settingsCard(
            context,
            ListTile(
              leading: Icon(
                Icons.error_outline,
                color: theme.colorScheme.error,
              ),
              title: const Text('导出未完成'),
              subtitle: SelectableText(
                _error!,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        if (_result != null)
          _settingsCard(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('导出完成'),
                  subtitle: Text('请从导出目录中的程序启动便携版，当前安装版继续正常运行。\n$_result'),
                ),
                Padding(
                  padding: const EdgeInsets.all(kDefaultPadding),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => OpenFilex.open(_result!),
                      icon: const Icon(Icons.folder_open),
                      label: const Text('打开导出文件夹'),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
