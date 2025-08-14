import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

import 'package:fml/pages/download child/loader/DownloadVanilla.dart';
import 'package:fml/pages/download child/loader/DownloadFabric.dart';
import 'package:fml/pages/download child/loader/DownloadTest.dart';

class DownloadGamePage extends StatefulWidget {
  DownloadGamePage({super.key, required this.type, required this.version, required this.url});

  final String type;
  final String version;
  final String url;

  @override
  _DownloadGamePageState createState() => _DownloadGamePageState();
}

class _DownloadGamePageState extends State<DownloadGamePage> {
  final Dio dio = Dio();
  String _selectedLoader = 'Vanilla';
  late final TextEditingController _gameNameController;
  String _gameName = '';
  List<String> _VersionList = [];
  List<String> _FabricVersionList = [];
  List<bool> _FabricStableList = [];
  List<dynamic> _FabricJson = [];
  String _appVersion = "unknown";
  bool _isLoading = true;
  String? _error;
  bool _showUnstable = false;
  String _selectedFabricVersion = '';
  Map<String, dynamic>? _selectedFabricLoader;

  // 读取版本列表
  Future<void> _loadVersionList() async {
    final prefs = await SharedPreferences.getInstance();
    final SelectedPath = prefs.getString('SelectedPath') ?? '';
    final GameList = prefs.getStringList('Game_$SelectedPath') ?? [];
    setState(() {
      _VersionList = GameList;
    });
  }

  Future<void> _loadAppVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final version = prefs.getString('version') ?? "1.0.0";
    setState(() {
      _appVersion = version;
    });
  }


  // 读取Fabric版本列表
  Future<void> _loadFabricList() async {
    debugPrint('加载${widget.version}Fabric版本列表');
    await _loadAppVersion();
    try {
      final options = Options(
        headers: {
          'User-Agent': 'FML/$_appVersion',
        },
      );
      // FML UA请求BMCLAPI Fabric
      final response = await dio.get(
        'https://bmclapi2.bangbang93.com/fabric-meta/v2/versions/loader/${widget.version}',
        options: options,
      );
      if (response.statusCode == 200) {
        List<dynamic> loaderData = response.data;
        List<String> versions = [];
        for (var loader in loaderData) {
          if (loader['loader'] != null && loader['loader']['version'] != null) {
            versions.add(loader['loader']['version']);
            bool isStable = loader['loader']['stable'] ?? false;
            _FabricStableList.add(isStable);
          }
        }
        setState(() {
          _FabricVersionList = versions;
          _FabricJson = loaderData;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = '请求失败：状态码 ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '请求出错: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _gameNameController = TextEditingController();
    _gameNameController.text = widget.version;
    _gameName = widget.version;
    _loadVersionList();
    _loadFabricList();
  }

  @override
  void dispose() {
    _gameNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('下载${widget.version}'),
      ),
      body: Center(
        child: ListView(
          children: [
            Card(
              child: ListTile(
                title: Text('版本: ${widget.version}'),
                subtitle: Text('类型: ${widget.type}'),
                leading: Icon(
                  widget.type == 'release' ? Icons.check_circle : Icons.science,
                ),
              ),
            ),
            Card(
              child: TextField(
                controller: _gameNameController,
                decoration: InputDecoration(
                  labelText: '游戏名称',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() {
                  _gameName = value;
                }),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('模组加载器'),
                    DropdownButton<String>(
                      value: _selectedLoader,
                      hint: const Text('选择模组加载器'),
                      items: [
                        DropdownMenuItem<String>(
                          value: 'Vanilla',
                          child: const Text('不安装模组加载器'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'Fabric',
                          child: const Text('Fabric'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'NeoForge',
                          child: const Text('NeoForge'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedLoader = value!;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (_selectedLoader == 'Fabric') ...[
              Card(
                  child: SwitchListTile(
                    title: const Text('显示不稳定版本'),
                    value: _showUnstable,
                    onChanged: (value) {
                      setState(() {
                        _showUnstable = value;
                      });
                    },
                  ),
                ),
                ..._FabricVersionList
                    .where((version) => _showUnstable || _FabricStableList[_FabricVersionList.indexOf(version)])
                    .map(
                      (version) => Card(
                        child: ListTile(
                          title: Text(version),
                          subtitle: _FabricStableList[_FabricVersionList.indexOf(version)]
                              ? const Text('稳定版本')
                              : const Text('不稳定版本'),
                          onTap: () {
                            final index = _FabricVersionList.indexOf(version);
                            setState(() {
                              _selectedFabricVersion = version;
                              _selectedFabricLoader = _FabricJson[index]; // 保存对应的完整JSON对象
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已选择Fabric版本: $version')),
                            );
                          },
                        ),
                      ),
                    )
            ],
            if (_selectedLoader == 'NeoForge') ...[
              Card(
                child: ListTile(
                  title: Text('NeoForge特有设置'),
                ),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_gameName.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('游戏名称不能为空')),
            );
            return;
          }
          if (_VersionList.contains(_gameName)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('该游戏名称已存在，请换一个名称')),
            );
            return;
          }
          if (_selectedLoader == 'Vanilla') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => DownloadVanillaPage(version: widget.version, url: widget.url, name: _gameName)),
            );
          }
          if (_selectedLoader == 'Fabric') {
            if (_selectedFabricVersion.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请先选择Fabric版本')),
              );
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => DownloadFabricPage(version: widget.version, url: widget.url, name: _gameName, fabricVersion: _selectedFabricVersion, fabricLoader: _selectedFabricLoader,)),
            );
          }
        },
        child: const Icon(Icons.download),
      ),
    );
  }
}