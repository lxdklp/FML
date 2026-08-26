import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:fml/pages/home/management/game_settings.dart';
import 'package:fml/pages/home/management/mod_management.dart';
import 'package:fml/pages/home/management/resourcepack_management.dart';
import 'package:fml/pages/home/management/shaderpack_management.dart';
import 'package:fml/pages/home/management/schematic_management.dart';
import 'package:fml/pages/home/management/saves_management.dart';

class ManagementPage extends StatefulWidget {
  const ManagementPage({super.key});

  @override
  ManagementPageState createState() => ManagementPageState();
}

class ManagementPageState extends State<ManagementPage>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  String _gamePath = '';
  String _logsPath = '';
  String _savesPath = '';
  String _screenshotsPath = '';
  String _resourcepacksPath = '';
  String _modsPath = '';
  String _shaderpacksPath = '';
  String _schematicsPath = '';
  bool _save = false;
  bool _screenshots = false;
  bool _logs = false;
  bool _resourcepacks = false;
  bool _mods = false;
  bool _shaderpacks = false;
  bool _schematics = false;
  bool _isLoading = true;

  // 动态 Tab 列表
  List<_TabInfo> _tabs = [];

  @override
  void initState() {
    super.initState();
    _loadGamePath();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  // 加载游戏路径
  Future<void> _loadGamePath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('SelectedPath') ?? '';
    final game = prefs.getString('SelectedGame') ?? '';
    final gamePath = prefs.getString('Path_$path') ?? '';
    final fullPath =
        '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game';
    String finalGamePath;
    if (Platform.isWindows) {
      finalGamePath = fullPath.substring(0, 2) + fullPath.substring(3);
    } else {
      finalGamePath = fullPath;
    }
    setState(() {
      _gamePath = finalGamePath;
    });
    await _checkDirectory();
  }

  // 检查文件夹是否存在
  Future<bool> _checkDirectoryFuture(String path) async {
    final dir = Directory(path);
    return await dir.exists();
  }

  // 检查各个管理文件夹
  Future<void> _checkDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedPath = prefs.getString('SelectedPath') ?? '';
    final game = prefs.getString('SelectedGame') ?? '';
    final gamePath = prefs.getString('Path_$selectedPath') ?? '';
    final path =
        '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game';
    // 检查存档文件夹
    final savesExists = await _checkDirectoryFuture(
      '$path${Platform.pathSeparator}saves',
    );
    if (savesExists) {
      _save = true;
      _savesPath = '$_gamePath${Platform.pathSeparator}saves';
    }
    // 检查截图文件夹
    final screenshotsExists = await _checkDirectoryFuture(
      '$path${Platform.pathSeparator}screenshots',
    );
    if (screenshotsExists) {
      _screenshots = true;
      _screenshotsPath = '$_gamePath${Platform.pathSeparator}screenshots';
    }
    // 检查日志文件夹
    final logsExists = await _checkDirectoryFuture(
      '$path${Platform.pathSeparator}logs',
    );
    if (logsExists) {
      _logs = true;
      _logsPath = '$_gamePath${Platform.pathSeparator}logs';
    }
    // 检查资源包文件夹
    final resourcepacksExists = await _checkDirectoryFuture(
      '$path${Platform.pathSeparator}resourcepacks',
    );
    if (resourcepacksExists) {
      _resourcepacks = true;
      _resourcepacksPath = '$_gamePath${Platform.pathSeparator}resourcepacks';
    }
    // 检查模组文件夹
    final modsExists = await _checkDirectoryFuture(
      '$path${Platform.pathSeparator}mods',
    );
    if (modsExists) {
      _mods = true;
      _modsPath = '$_gamePath${Platform.pathSeparator}mods';
    }
    // 检查光影文件夹
    final shaderpacksExists = await _checkDirectoryFuture(
      '$path${Platform.pathSeparator}shaderpacks',
    );
    if (shaderpacksExists) {
      _shaderpacks = true;
      _shaderpacksPath = '$_gamePath${Platform.pathSeparator}shaderpacks';
    }
    // 检查原理图文件夹
    final schematicsExists = await _checkDirectoryFuture(
      '$path${Platform.pathSeparator}schematics',
    );
    if (schematicsExists) {
      _schematics = true;
      _schematicsPath = '$_gamePath${Platform.pathSeparator}schematics';
    }
    _buildTabs();
    setState(() {
      _isLoading = false;
    });
  }

  // 构建 Tab 列表
  Future<void> _buildTabs() async {
    _tabs = [];
    _tabs.add(
      _TabInfo(
        tab: const Tab(text: '游戏设置'),
        content: GameSettingsTab(
          gamePath: _gamePath,
          savesPath: _savesPath,
          screenshotsPath: _screenshotsPath,
          logsPath: _logsPath,
          resourcepacksPath: _resourcepacksPath,
          modsPath: _modsPath,
          shaderpacksPath: _shaderpacksPath,
          schematicsPath: _schematicsPath,
          hasSaves: _save,
          hasScreenshots: _screenshots,
          hasLogs: _logs,
        ),
      ),
    );
    // 模组管理
    if (_mods) {
      _tabs.add(
        _TabInfo(
          tab: const Tab(text: 'Mod管理'),
          content: ModManagementTab(modsPath: _modsPath),
        ),
      );
    }
    // 资源包管理
    if (_resourcepacks) {
      _tabs.add(
        _TabInfo(
          tab: const Tab(text: '资源包管理'),
          content: ResourcepackManagementTab(
            resourcepacksPath: _resourcepacksPath,
          ),
        ),
      );
    }
    // 光影管理
    if (_shaderpacks) {
      _tabs.add(
        _TabInfo(
          tab: const Tab(text: '光影管理'),
          content: ShaderpackManagementTab(shaderpacksPath: _shaderpacksPath),
        ),
      );
    }
    // 原理图管理
    if (_schematics) {
      _tabs.add(
        _TabInfo(
          tab: const Tab(text: '原理图管理'),
          content: SchematicManagementTab(schematicsPath: _schematicsPath),
        ),
      );
    }
    // 存档管理
    if (_save) {
      _tabs.add(
        _TabInfo(
          tab: const Tab(text: '存档管理'),
          content: SavesManagementTab(savesPath: _savesPath),
        ),
      );
    }
    // 初始化 TabController
    if (_tabs.length > 1) {
      _tabController = TabController(length: _tabs.length, vsync: this);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('版本管理')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    // 只有游戏设置页面时隐藏 Tab 栏
    if (_tabs.length == 1) {
      return Scaffold(
        appBar: AppBar(title: const Text('版本管理')),
        body: _tabs.first.content,
      );
    }
    // 有多个 Tab 时显示 Tab 栏
    return Scaffold(
      appBar: AppBar(
        title: const Text('版本管理'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs.map((t) => t.tab).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((t) => t.content).toList(),
      ),
    );
  }
}

class _TabInfo {
  final Tab tab;
  final Widget content;

  _TabInfo({required this.tab, required this.content});
}
