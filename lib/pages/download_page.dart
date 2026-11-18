import 'package:material_ui/material_ui.dart';
import 'package:fml/constants.dart';
import 'package:fml/pages/download/download_resources.dart';
import 'package:fml/pages/download/download_version.dart';
import 'package:flutter/foundation.dart';
import 'package:fml/pages/download/mmc_import.dart';
import 'package:file_picker/file_picker.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key, this.active});

  final ValueListenable<bool>? active;

  @override
  DownloadPageState createState() => DownloadPageState();
}

class DownloadPageState extends State<DownloadPage> {
  int _selectedIndex = 0;
  bool _resourcesPageInitialized = false;
  bool _openingImport = false;

// 打开导入整合包文件, 如果archivePath为null则弹出文件选择器
  Future<void> _openImport({String? archivePath}) async {
    if (_openingImport ||
        !(widget.active?.value ?? true) ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    setState(() => _openingImport = true);
    try {
      if (archivePath == null) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['zip'],
        );
        if (result == null) return;
        archivePath = result.files.single.path;
        if (archivePath == null) throw StateError('无法获取所选文件的路径');
      }
      if (!mounted ||
          !(widget.active?.value ?? true) ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      await openMmcImport(context, archivePath: archivePath);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开整合包文件: $error')));
      }
    } finally {
      if (mounted) setState(() => _openingImport = false);
    }
  }

  static const List<NavigationDrawerDestination> _destinations = [
    NavigationDrawerDestination(icon: Icon(Icons.code), label: Text('游戏')),
    NavigationDrawerDestination(icon: Icon(Icons.extension), label: Text('资源')),
  ];

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: widget.active ?? const AlwaysStoppedAnimation(true),
      builder: (context, active, _) => MmcImportDropTarget(
        enabled: active && !_openingImport,
        onDrop: (path) => _openImport(archivePath: path),
        child: Material(
          child: LayoutBuilder(
            builder: (context, constraints) {
              double sidebarWidth = (constraints.maxWidth * 0.25).clamp(
                150.0,
                320.0,
              );
              return Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: theme.dividerColor.withAlpha(100),
                        ),
                      ),
                    ),
                    child: SizedBox(
                      width: sidebarWidth,
                      child: NavigationDrawer(
                        selectedIndex: _selectedIndex,
                        onDestinationSelected: (index) {
                          if (_selectedIndex == index) return;
                          FocusScope.of(context).unfocus();
                          setState(() {
                            _selectedIndex = index;
                            if (index == 1) _resourcesPageInitialized = true;
                          });
                        },
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              kDefaultPadding * 1.5,
                              kDefaultPadding,
                              kDefaultPadding,
                              kDefaultPadding,
                            ),
                            child: Text(
                              '下载',
                              style: theme.textTheme.headlineMedium,
                            ),
                          ),
                          for (var dest in _destinations) dest,
                          const Divider(),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: active && !_openingImport
                                      ? () => _openImport()
                                      : null,
                                  icon: const Icon(Icons.folder_zip_outlined),
                                  label: const Text('导入整合包'),
                                ),
                                const SizedBox(height: 8),
                                const Text('选择或拖入 MMC / Prism ZIP'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: _selectedIndex,
                      children: [
                        const DownloadVersionPage(),
                        _resourcesPageInitialized
                            ? const DownloadResources()
                            : const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
