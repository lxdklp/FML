import 'package:flutter/material.dart';
import 'package:fml/constants.dart';
import 'package:fml/function/dio_client.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:fml/model/minecraft_version.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

import 'package:fml/function/log.dart';
import 'package:fml/pages/download/download_version/loader/download_vanilla.dart';
import 'package:fml/pages/download/download_version/loader/download_fabric.dart';
import 'package:fml/pages/download/download_version/loader/download_neoforge.dart';

class DownloadGamePage extends StatefulWidget {
  const DownloadGamePage({super.key, required this.version});

  final MinecraftVersion version;

  @override
  DownloadGamePageState createState() => DownloadGamePageState();
}

///
/// TODO: Forge support
///
class DownloadGamePageState extends State<DownloadGamePage> {
  late final TextEditingController _gameNameController;
  String _gameFolderName = '';

  String _selectedLoader = 'Vanilla';
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
    LogUtil.log('加载${widget.version.id} Fabric版本列表', level: 'INFO');

    try {
      // 请求BMCLAPI Fabric
      final response = await DioClient().dio.get(
        'https://bmclapi2.bangbang93.com/fabric-meta/v2/versions/loader/${widget.version.id}',
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
    LogUtil.log('加载${widget.version.id} NeoForge版本列表', level: 'INFO');

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
          if (widget.version.id.startsWith('1.')) {
            String versionWithoutPrefix = widget.version.id.substring(2);
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
    _gameNameController.text = widget.version.id;
    _gameFolderName = widget.version.id;
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
    List<DropdownMenuItem<String>> modLoadersDropdownMenuItem = [
      DropdownMenuItem<String>(value: 'Vanilla', child: const Text('不安装模组加载器')),
      DropdownMenuItem<String>(value: 'Fabric', child: const Text('Fabric')),
      DropdownMenuItem<String>(
        value: 'NeoForge',
        child: const Text('NeoForge'),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text('安装 ${widget.version.id}')),

      body: Padding(
        padding: const EdgeInsets.all(kDefaultPadding),
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: kDefaultPadding / 2,
                horizontal: kDefaultPadding,
              ),
              child: TextField(
                controller: _gameNameController,
                decoration: InputDecoration(
                  labelText: '游戏文件夹名称',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() {
                  _gameFolderName = value;
                }),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: kDefaultPadding / 2,
                horizontal: kDefaultPadding,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('模组加载器'),
                  DropdownButton<String>(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kDefaultPadding,
                    ), // 添加左右内边距
                    underline: const SizedBox(), // 去除底部下划线
                    value: _selectedLoader,
                    hint: const Text('选择模组加载器'),

                    items: modLoadersDropdownMenuItem,
                    onChanged: (value) {
                      setState(() {
                        _selectedLoader = value!;
                      });
                    },
                  ),
                ],
              ),
            ),

            if (_selectedLoader == 'Fabric') ...[
              SwitchListTile(
                title: Text(
                  '显示不稳定版本',
                  style: Theme.of(context).textTheme.bodyMedium, // 统一字体
                ),
                value: _showUnstable,
                onChanged: (value) {
                  setState(() {
                    _showUnstable = value;
                  });
                },
              ),

              if (_showUnstable)
                // 分割线
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: kDefaultPadding / 2),
                  child: Divider(height: 1),
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
              SwitchListTile(
                title: Text(
                  '显示测试版',
                  style: Theme.of(context).textTheme.bodyMedium, // 统一字体
                ),
                value: _showNeoForgeUnstable,
                onChanged: (value) {
                  setState(() {
                    _showNeoForgeUnstable = value;
                  });
                },
              ),

              if (_showNeoForgeUnstable)
                // 分割线
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: kDefaultPadding / 2),
                  child: Divider(height: 1),
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
          if (_gameFolderName.isEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('游戏文件夹名称不能为空')));
            return;
          }

          if (_versionList.contains(_gameFolderName)) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('该游戏文件夹已存在，请换一个名称')));
            return;
          }

          switch (_selectedLoader) {
            case "Vanilla":
              Navigator.push(
                context,
                SlidePageRoute(
                  page: DownloadVanillaPage(
                    version: widget.version.id,
                    url: widget.version.id,
                    name: _gameFolderName,
                  ),
                ),
              );
              break;

            case "Fabric":
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
                    version: widget.version.id,
                    url: widget.version.url,
                    name: _gameFolderName,
                    fabricVersion: _selectedFabricVersion,
                    fabricLoader: _selectedFabricLoader,
                  ),
                ),
              );
              break;

            case "NeoForge":
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
                    version: widget.version.id,
                    url: widget.version.url,
                    name: _gameFolderName,
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
