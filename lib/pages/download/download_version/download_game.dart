import 'package:flutter/material.dart';
import 'package:fml/constants.dart';
import 'package:fml/function/dio_client.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:fml/models/minecraft_version.dart';
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
  String _versionFolderName = '';
  late final TextEditingController _versionFolderController;

  final _formKey = GlobalKey<FormState>();
  // 用于跟踪Form是否有效
  bool _isFormValid = false;

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

  @override
  void initState() {
    super.initState();
    _versionFolderController = TextEditingController();
    _versionFolderController.text = widget.version.id;
    _versionFolderName = widget.version.id;

    //检查一次初始文本是否有效
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _isFormValid = _formKey.currentState?.validate() ?? false;
      });
    });

    _loadVersionList();
    _loadFabricList();
    _loadNeoForgeList();
  }

  @override
  void dispose() {
    _versionFolderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              child: Form(
                key: _formKey,

                child: TextFormField(
                  autofocus: true,
                  controller: _versionFolderController,
                  decoration: InputDecoration(
                    labelText: '版本名称',
                    border: const OutlineInputBorder(),
                  ),

                  // 实时验证输入内容
                  autovalidateMode: AutovalidateMode.onUserInteraction,

                  onChanged: (value) => setState(() {
                    _versionFolderName = value;

                    // 更新状态变量
                    _isFormValid = _formKey.currentState!.validate();
                  }),

                  // 检测文本输入是否有效
                  validator: (String? value) {
                    // TODO:添加更多检测，包装一个检查路径的Util

                    // 判断是否为空
                    if (value == null || value.isEmpty) {
                      return '文件夹名称不能为空';
                    }

                    // 判断是否已经存在
                    final String folderName = value.trim();
                    if (_versionList.contains(folderName)) {
                      return "已存在名为 '$folderName' 的文件夹！";
                    }

                    // 所有检查通过
                    return null;
                  },
                ),
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

                    items: modLoadersDropdownMenuItems,
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
          // 表单检测无效时直接禁用点击
          if (!_isFormValid) {
            return;
          }

          switch (_selectedLoader) {
            case "Vanilla":
              Navigator.push(
                context,
                SlidePageRoute(
                  page: DownloadVanillaPage(
                    version: widget.version.id,
                    url: widget.version.url,
                    name: _versionFolderName,
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
                    name: _versionFolderName,
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
                    name: _versionFolderName,
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

  static final List<DropdownMenuItem<String>> modLoadersDropdownMenuItems =
      const [
        DropdownMenuItem<String>(value: 'Vanilla', child: Text('不安装模组加载器')),
        DropdownMenuItem<String>(value: 'Fabric', child: Text('Fabric')),
        DropdownMenuItem<String>(value: 'NeoForge', child: Text('NeoForge')),
      ];

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

    if (!mounted) return;

    setState(() {
      _versionList = gameList;
      _isFormValid = _formKey.currentState?.validate() ?? false;
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

        if (!mounted) return;

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

        if (!mounted) return;

        setState(() {
          _neoForgeStableVersions = stableVersions;
          _neoforgeBetaVersions = betaVersions;
        });
      }
    } catch (e) {
      LogUtil.log('请求出错: $e', level: 'ERROR');
    }
  }
}
