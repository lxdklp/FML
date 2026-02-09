import 'package:flutter/material.dart';
import 'package:fml/function/dio_client.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

import 'package:fml/function/log.dart';
import 'package:fml/pages/download/download_version/loader/download_vanilla.dart';
import 'package:fml/pages/download/download_version/loader/download_fabric.dart';
import 'package:fml/pages/download/download_version/loader/download_neoforge.dart';

class DownloadGamePage extends StatefulWidget {
  const DownloadGamePage({
    super.key,
    required this.type,
    required this.version,
    required this.url,
  });

  final String type;
  final String version;
  final String url;

  @override
  DownloadGamePageState createState() => DownloadGamePageState();
}

class DownloadGamePageState extends State<DownloadGamePage> {
  String _selectedLoader = 'Vanilla';
  late final TextEditingController _gameNameController;
  String _gameName = '';
  List<String> _versionList = [];
  List<String> _fabricVersionList = [];
  final List<bool> _fabricStableList = [];
  List<dynamic> _fabricJson = [];
  bool _showUnstable = false;
  String _selectedFabricVersion = '';
  Map<String, dynamic>? _selectedFabricLoader;
  List<String> _neoForgeStableVersions = [];
  List<String> _neoforgeBetaVersions = [];
  String _selectedNeoForgeVersion = '';
  bool _showNeoForgeUnstable = false;

  int _compareVersions(String versionA, String versionB) {
    String cleanA = versionA.replaceAll('-beta', '');
    String cleanB = versionB.replaceAll('-beta', '');
    List<int> partsA = cleanA.split('.').map(int.parse).toList();
    List<int> partsB = cleanB.split('.').map(int.parse).toList();
    for (int i = 0; i < max(partsA.length, partsB.length); i++) {
      int partA = i < partsA.length ? partsA[i] : 0;
      int partB = i < partsB.length ? partsB[i] : 0;
      if (partA != partB) {
        return partA.compareTo(partB);
      }
    }
    return 0;
  }

  // 读取版本列表
  Future<void> _loadVersionList() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedPath = prefs.getString('SelectedPath') ?? '';
    final gameList = prefs.getStringList('Game_$selectedPath') ?? [];
    setState(() {
      _versionList = gameList;
    });
  }

  // 读取Fabric版本列表
  Future<void> _loadFabricList() async {
    LogUtil.log('加载${widget.version}Fabric版本列表', level: 'INFO');

    try {
      // 请求BMCLAPI Fabric
      final response = await DioClient().dio.get(
        'https://bmclapi2.bangbang93.com/fabric-meta/v2/versions/loader/${widget.version}',
      );
      if (response.statusCode == 200) {
        List<dynamic> loaderData = response.data;
        List<String> versions = [];
        for (var loader in loaderData) {
          if (loader['loader'] != null && loader['loader']['version'] != null) {
            versions.add(loader['loader']['version']);
            bool isStable = loader['loader']['stable'] ?? false;
            _fabricStableList.add(isStable);
          }
        }
        setState(() {
          _fabricVersionList = versions;
          _fabricJson = loaderData;
        });
      }
    } catch (e) {
      LogUtil.log('请求出错: $e', level: 'ERROR');
    }
  }

  // 加载NeoForge
  Future<void> _loadNeoForgeList() async {
    LogUtil.log('加载${widget.version}NeoForge版本列表', level: 'INFO');

    try {
      final response = await DioClient().dio.get(
        'https://bmclapi2.bangbang93.com/maven/net/neoforged/neoforge/maven-metadata.xml',
      );
      if (response.statusCode == 200) {
        // 解析XML数据
        final xmlString = response.data.toString();
        List<String> stableVersions = [];
        List<String> betaVersions = [];
        RegExp versionRegExp = RegExp(r'<version>([^<]+)</version>');
        final matches = versionRegExp.allMatches(xmlString);
        for (var match in matches) {
          String version = match.group(1) ?? '';
          if (version.isNotEmpty) {
            if (version.contains('-beta')) {
              betaVersions.add(version);
            } else {
              stableVersions.add(version);
            }
          }
        }
        // 获取版本前缀
        String mcVersionPrefix = '';
        try {
          if (widget.version.startsWith('1.')) {
            String versionWithoutPrefix = widget.version.substring(2);
            mcVersionPrefix = versionWithoutPrefix;
          }
        } catch (e) {
          LogUtil.log('版本号解析错误: $e', level: 'ERROR');
        }
        // 过滤版本
        if (mcVersionPrefix.isNotEmpty) {
          stableVersions = stableVersions
              .where((v) => v.startsWith(mcVersionPrefix))
              .toList();
          betaVersions = betaVersions
              .where((v) => v.startsWith(mcVersionPrefix))
              .toList();
        }
        // 按版本号排序
        stableVersions.sort((a, b) => _compareVersions(b, a));
        betaVersions.sort((a, b) => _compareVersions(b, a));
        setState(() {
          _neoForgeStableVersions = stableVersions;
          _neoforgeBetaVersions = betaVersions;
        });
      }
    } catch (e) {
      LogUtil.log('请求出错: $e', level: 'ERROR');
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
    _loadNeoForgeList();
  }

  @override
  void dispose() {
    _gameNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('下载${widget.version}')),
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
              ..._fabricVersionList
                  .where(
                    (version) =>
                        _showUnstable ||
                        _fabricStableList[_fabricVersionList.indexOf(version)],
                  )
                  .map(
                    (version) => Card(
                      child: ListTile(
                        title: Text(version),
                        subtitle:
                            _fabricStableList[_fabricVersionList.indexOf(
                              version,
                            )]
                            ? const Text('稳定版')
                            : const Text('测试版'),
                        onTap: () {
                          final index = _fabricVersionList.indexOf(version);
                          setState(() {
                            _selectedFabricVersion = version;
                            _selectedFabricLoader =
                                _fabricJson[index]; // 保存对应的完整JSON对象
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('已选择Fabric版本: $version')),
                          );
                        },
                      ),
                    ),
                  ),
            ],
            if (_selectedLoader == 'NeoForge') ...[
              Card(
                child: SwitchListTile(
                  title: const Text('显示测试版'),
                  value: _showNeoForgeUnstable,
                  onChanged: (value) {
                    setState(() {
                      _showNeoForgeUnstable = value;
                    });
                  },
                ),
              ),
              ..._neoForgeStableVersions.map(
                (version) => Card(
                  child: ListTile(
                    title: Text(version),
                    subtitle: Text('稳定版'),
                    onTap: () {
                      setState(() {
                        _selectedNeoForgeVersion = version;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已选择NeoForge版本: $version')),
                      );
                    },
                  ),
                ),
              ),
              if (_showNeoForgeUnstable) ...[
                ..._neoforgeBetaVersions.map(
                  (version) => Card(
                    child: ListTile(
                      title: Text(version),
                      subtitle: Text('测试版'),
                      onTap: () {
                        setState(() {
                          _selectedNeoForgeVersion = version;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已选择NeoForge版本: $version')),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_gameName.isEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('游戏名称不能为空')));
            return;
          }
          if (_versionList.contains(_gameName)) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('该游戏名称已存在，请换一个名称')));
            return;
          }
          if (_selectedLoader == 'Vanilla') {
            Navigator.push(
              context,
              SlidePageRoute(
                page: DownloadVanillaPage(
                  version: widget.version,
                  url: widget.url,
                  name: _gameName,
                ),
              ),
            );
          }
          if (_selectedLoader == 'Fabric') {
            if (_selectedFabricVersion.isEmpty) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('请先选择Fabric版本')));
              return;
            }
            Navigator.push(
              context,
              SlidePageRoute(
                page: DownloadFabricPage(
                  version: widget.version,
                  url: widget.url,
                  name: _gameName,
                  fabricVersion: _selectedFabricVersion,
                  fabricLoader: _selectedFabricLoader,
                ),
              ),
            );
          }
          if (_selectedLoader == 'NeoForge') {
            if (_selectedNeoForgeVersion.isEmpty) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('请先选择NeoForge版本')));
              return;
            }
            Navigator.push(
              context,
              SlidePageRoute(
                page: DownloadNeoForgePage(
                  version: widget.version,
                  url: widget.url,
                  name: _gameName,
                  neoforgeVersion: _selectedNeoForgeVersion,
                ),
              ),
            );
          }
        },
        child: const Icon(Icons.download),
      ),
    );
  }
}
