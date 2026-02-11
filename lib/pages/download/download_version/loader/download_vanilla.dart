import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io';
import 'dart:convert';
import 'package:system_info2/system_info2.dart';

import 'package:fml/function/download.dart';
import 'package:fml/function/extract_natives.dart';
import 'package:fml/function/log.dart';

class DownloadVanillaPage extends StatefulWidget {
  const DownloadVanillaPage({
    super.key,
    required this.version,
    required this.url,
    required this.name
  });

  final String version;
  final String url;
  final String name;

  @override
  DownloadVanillaPageState createState() => DownloadVanillaPageState();
}

class DownloadVanillaPageState extends State<DownloadVanillaPage> {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  double _progress = 0.0;
  bool _downloadJson = false;
  bool _parseGameJson = false;
  bool _parseAssetJson = false;
  bool _downloadAssetJson = false;
  bool _downloadClient = false;
  bool _downloadLibrary = false;
  bool _downloadAsset = false;
  bool _extractedLwjglNativesPath = false;
  bool _extractedLwjglNatives = false;
  bool _writeConfig = false;
  int _mem = 1;
  String _name = '';

  String? assetIndexURL;
  String? clientURL;
  String? assetIndexId;
  List<String> librariesPath = [];
  List<String> librariesURL = [];
  final List<String> _assetHash = [];
  List<String> lwjglNativeNames = [];
  List<String> lwjglNativePaths = [];

  // BMCLAPI 镜像
  String replaceWithMirror(String url) {
    return url
      .replaceAll('piston-meta.mojang.com', 'bmclapi2.bangbang93.com')
      .replaceAll('piston-data.mojang.com', 'bmclapi2.bangbang93.com')
      .replaceAll('launcher.mojang.com', 'bmclapi2.bangbang93.com')
      .replaceAll('launchermeta.mojang.com', 'bmclapi2.bangbang93.com')
      .replaceAll('libraries.minecraft.net', 'bmclapi2.bangbang93.com/maven')
      .replaceAll('resources.download.minecraft.net', 'bmclapi2.bangbang93.com/assets');
  }

  // 初始化通知
  Future<void> _initNotifications() async {
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      const DarwinInitializationSettings initializationSettingsDarwin =
          DarwinInitializationSettings();
      const LinuxInitializationSettings initializationSettingsLinux =
          LinuxInitializationSettings(defaultActionName: 'Open');
      const WindowsInitializationSettings initializationSettingsWindows =
          WindowsInitializationSettings(
            appName: 'FML',
            appUserModelId: 'lxdklp.fml',
            guid: '11451419-0721-0721-0721-114514191981',
          );
      const InitializationSettings initializationSettings = InitializationSettings(
        macOS: initializationSettingsDarwin,
        linux: initializationSettingsLinux,
        windows: initializationSettingsWindows,
      );
      await flutterLocalNotificationsPlugin.initialize(
        settings: initializationSettings,
      );
    }
  }

  // 弹出通知
  Future<void> _showNotification(String title, String body) async {
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails();
      const LinuxNotificationDetails linuxDetails = LinuxNotificationDetails();
      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        macOS: darwinDetails,
        linux: linuxDetails,
      );
      await flutterLocalNotificationsPlugin.show(
        id: 0,
        title: title,
        body: body,
        notificationDetails: platformChannelSpecifics,
      );
    }
  }

  // 文件夹创建
  Future<void> _createGameDirectories() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedGamePath = prefs.getString('SelectedPath') ?? '';
    final gamePath = prefs.getString('Path_$selectedGamePath') ?? '';
    final directory = Directory('$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
      await LogUtil.log('创建目录: $gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}', level: 'INFO');
    }
  }

  // 游戏Json解析
  Future<void> parseGameJson(String jsonFilePath) async {
    try {
      final file = File(jsonFilePath);
      if (!file.existsSync()) {
        throw Exception('JSON文件不存在: $jsonFilePath');
      }
      final jsonString = await file.readAsString();
      final jsonData = jsonDecode(jsonString);
      // 提取assetIndex URL和ID
      if (jsonData['assetIndex'] != null) {
        // 解析 URL
        if (jsonData['assetIndex']['url'] != null) {
          assetIndexURL = replaceWithMirror(jsonData['assetIndex']['url']);
        }
        // 解析 ID
        if (jsonData['assetIndex']['id'] != null) {
          assetIndexId = jsonData['assetIndex']['id'];
        }
      }
      // 提取client URL
      if (jsonData['downloads'] != null &&
          jsonData['downloads']['client'] != null &&
          jsonData['downloads']['client']['url'] != null) {
        clientURL = replaceWithMirror(jsonData['downloads']['client']['url']);
      }
      // 提取libraries的path和URL
      if (jsonData['libraries'] != null && jsonData['libraries'] is List) {
        for (var lib in jsonData['libraries']) {
          if (lib['downloads'] != null &&
              lib['downloads']['artifact'] != null) {
            final artifact = lib['downloads']['artifact'];
            if (artifact['path'] != null) {
              librariesPath.add(artifact['path']);
            }
            if (artifact['url'] != null) {
              // 替换URL为BMCLAPI镜像
              librariesURL.add(replaceWithMirror(artifact['url']));
            }
          }
        }
        await LogUtil.log('找到 ${librariesPath.length} 个库文件路径,找到 ${librariesURL.length} 个库文件URL', level: 'INFO');
      }
      setState(() {
        _parseGameJson = true;
      });
    } catch (e) {
        await _showNotification('解析JSON失败', e.toString());
        await LogUtil.log('解析JSON失败: $e', level: 'ERROR');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解析JSON失败: $e')),
        );
        setState(() {
          _parseGameJson = false;
      });
    }
  }

  // 解析Assset JSON
  Future<void> parseAssetIndex(String assetIndexPath) async {
    try {
      final file = File(assetIndexPath);
      if (!file.existsSync()) {
        throw Exception('资产索引文件不存在: $assetIndexPath');
      }
      final jsonString = await file.readAsString();
      final jsonData = jsonDecode(jsonString);
      _assetHash.clear();
      if (jsonData['objects'] == null) {
        throw Exception('资产索引JSON中缺少objects字段');
      }
      final objects = jsonData['objects'] as Map<String, dynamic>;
      objects.forEach((assetPath, info) {
        if (info['hash'] != null) {
          _assetHash.add(info['hash']);
        }
      });
      await LogUtil.log('已解析 ${_assetHash.length} 个资产哈希值', level: 'INFO');
      setState(() {
        _parseAssetJson = true;
      });
    } catch (e) {
      await _showNotification('解析资产索引失败', e.toString());
      await LogUtil.log('解析资产索引失败: $e', level: 'ERROR');
      setState(() {
        _parseAssetJson = false;
      });
    }
  }

  // 下载库
  Future<void> _downloadLibraries() async {
    if (librariesURL.isEmpty || librariesPath.isEmpty) {
      await _showNotification('库文件列表为空', '无法下载库文件');
      await LogUtil.log('库文件列表为空,无法下载库文件', level: 'ERROR');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final selectedGamePath = prefs.getString('SelectedPath') ?? '';
    final gamePath = prefs.getString('Path_$selectedGamePath') ?? '';
    List<Map<String, String>> downloadTasks = [];
    for (int i = 0; i < librariesURL.length; i++) {
      final url = librariesURL[i];
      final relativePath = librariesPath[i];
      final fullPath = '$gamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}$relativePath';
      final file = File(fullPath);
      if (!file.existsSync()) {
        downloadTasks.add({'url': url, 'path': fullPath});
      }
    }
    if (downloadTasks.isEmpty) {
      await LogUtil.log('所有库文件已存在,无需下载', level: 'INFO');
      setState(() {
        _downloadLibrary = true;
      });
      return;
    }
    final result = await DownloadUtils.batchDownload(
      tasks: downloadTasks,
      onProgress: (progress) {
        setState(() {
          _progress = progress;
        });
      },
      fileType: '库文件',
    );
    if (!result.success) {
      await LogUtil.log('库文件下载完成,失败 ${result.failedList.length} 个', level: 'WARNING');
    }
    setState(() {
      _downloadLibrary = true;
      _progress = 0;
    });
  }

  // 下载资源
  Future<void> _downloadAssets() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedGamePath = prefs.getString('SelectedPath') ?? '';
    final gamePath = prefs.getString('Path_$selectedGamePath') ?? '';
    List<Map<String, String>> downloadTasks = [];
    for (int i = 0; i < _assetHash.length; i++) {
      final hash = _assetHash[i];
      final hashPrefix = hash.substring(0, 2);
      final assetDir = '$gamePath${Platform.pathSeparator}assets${Platform.pathSeparator}objects${Platform.pathSeparator}$hashPrefix';
      final assetPath = '$assetDir${Platform.pathSeparator}$hash';
      final directory = Directory(assetDir);
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      final file = File(assetPath);
      if (!file.existsSync()) {
        final url = 'https://bmclapi2.bangbang93.com/assets/$hashPrefix/$hash';
        downloadTasks.add({'url': url, 'path': assetPath});
      }
    }
    if (downloadTasks.isEmpty) {
      await LogUtil.log('所有资源文件已存在,无需下载', level: 'INFO');
      setState(() {
        _downloadAsset = true;
      });
      return;
    }
    final result = await DownloadUtils.batchDownload(
      tasks: downloadTasks,
      onProgress: (progress) {
        setState(() {
          _progress = progress;
        });
      },
      fileType: '资源文件',
    );
    if (!result.success) {
      await LogUtil.log('资源文件下载完成,失败 ${result.failedList.length} 个', level: 'WARNING');
    }
    setState(() {
      _downloadAsset = true;
    });
  }

  // 提取LWJGL本地库文件的名称和路径
  Future<void> _extractLwjglNativeLibrariesPath(String jsonFilePath, String gamePath) async {
    final namesList = <String>[];
    final pathsList = <String>[];
    final file = File(jsonFilePath);
    if (!await file.exists()) {
      await LogUtil.log('版本JSON文件不存在: $jsonFilePath', level: 'ERROR');
      await _showNotification('提取LWJGL本地库失败', '版本JSON文件不存在');
      setState(() {
        lwjglNativeNames = namesList;
        lwjglNativePaths = pathsList;
      });
      return;
    }
    late final dynamic root;
    try {
      root = jsonDecode(await file.readAsString());
    } catch (e) {
      await LogUtil.log('JSON 解析失败: $e', level: 'ERROR');
      await _showNotification('提取LWJGL本地库失败', e.toString());
      setState(() {
        lwjglNativeNames = namesList;
        lwjglNativePaths = pathsList;
      });
      return;
    }
    final libs = root is Map ? root['libraries'] : null;
    if (libs is! List) {
      await LogUtil.log('JSON中没有libraries字段或格式错误', level: 'ERROR');
      await _showNotification('提取LWJGL本地库失败', 'JSON中没有libraries字段或格式错误');
      setState(() {
        lwjglNativeNames = namesList;
        lwjglNativePaths = pathsList;
      });
      return;
    }
    for (final item in libs) {
      if (item is! Map) continue;
      final downloads = item['downloads'];
      if (downloads is! Map) continue;
      final artifact = downloads['artifact'];
      if (artifact is! Map) continue;
      final path = artifact['path'];
      if (path is! String || path.isEmpty) continue;
      final fileName = path.split('/').last;
      // 检查是否为所需的LWJGL库
      if ((fileName.startsWith('lwjgl-') && fileName.contains('-natives-')) ||
          (fileName.startsWith('lwjgl-freetype-') && fileName.contains('-natives-')) ||
          (fileName.startsWith('lwjgl-glfw-') && fileName.contains('-natives-')) ||
          (fileName.startsWith('lwjgl-jemalloc-') && fileName.contains('-natives-')) ||
          (fileName.startsWith('lwjgl-openal-') && fileName.contains('-natives-')) ||
          (fileName.startsWith('lwjgl-stb-') && fileName.contains('-natives-')) ||
          fileName.startsWith('lwjgl-tinyfd')) {
        namesList.add(fileName);
        String nativePath = path.replaceAll('/', Platform.pathSeparator);
        final fullPath = ('$gamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}$nativePath');
        pathsList.add(fullPath);
        await LogUtil.log('找到LWJGL库: $fileName, 路径: $fullPath', level: 'INFO');
      }
    }
    await LogUtil.log('总共找到${namesList.length}个LWJGL本地库', level: 'INFO');
    setState(() {
      lwjglNativeNames = namesList;
      lwjglNativePaths = pathsList;
      _extractedLwjglNativesPath = true;
    });
  }

  // 提取LWJGL Natives
  Future<void> _extractLwjglNatives() async {
    if (lwjglNativePaths.isEmpty || lwjglNativeNames.isEmpty) {
      await LogUtil.log('没有找到LWJGL本地库,跳过提取', level: 'WARNING');
      setState(() {
        _extractedLwjglNativesPath = true;
      });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final selectedGamePath = prefs.getString('SelectedPath') ?? '';
    final gamePath = prefs.getString('Path_$selectedGamePath') ?? '';
    final nativesDir = '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}${Platform.pathSeparator}natives';
    final nativesDirObj = Directory(nativesDir);
    if (!await nativesDirObj.exists()) {
      await nativesDirObj.create(recursive: true);
      await LogUtil.log('创建natives目录: $nativesDir', level: 'INFO');
    }
    await LogUtil.log('开始提取LWJGL本地库到: $nativesDir', level: 'INFO');
    int successCount = 0;
    List<String> extractedFiles = [];
    for (int i = 0; i < lwjglNativePaths.length; i++) {
      final fullPath = lwjglNativePaths[i];
      final fileName = lwjglNativeNames[i];
      try {
        final jarDir = fullPath.substring(0, fullPath.lastIndexOf(Platform.pathSeparator));
        await LogUtil.log('提取: $fileName 从 $jarDir 到 $nativesDir', level: 'INFO');
        // 调用extractNatives函数提取本地库
        final extracted = await extractNatives(jarDir, fileName, nativesDir);
        if (extracted.isNotEmpty) {
          successCount++;
          extractedFiles.addAll(extracted);
          await LogUtil.log('成功从 $fileName 提取了 ${extracted.length} 个文件', level: 'INFO');
        }
      } catch (e) {
        await LogUtil.log('提取 $fileName 时出错: $e', level: 'ERROR');
      }
    }
    await LogUtil.log('完成LWJGL本地库提取, 共处理 ${lwjglNativePaths.length} 个文件, 成功: $successCount', level: 'INFO');
    await LogUtil.log('提取的文件: ${extractedFiles.join(', ')}', level: 'INFO');
    setState(() {
      _extractedLwjglNatives = true;
    });
  }

  // 文件下载
  Future<void> _downloadFile(path, url) async {
    bool success = false;
    try {
      await DownloadUtils.downloadFile(
        url: url,
        savePath: path,
        onProgress: (progress) {
          setState(() {
            _progress = progress;
          });
        },
        onSuccess: () {
          success = true;
        },
        onError: (error) async {
          await LogUtil.log('下载失败: $error, URL: $url', level: 'ERROR');
        }
      );
      final file = File(path);
      if (await file.exists()) {
        success = true;
      }
      if (!success) {
        throw Exception('下载失败: $url');
      }
    } catch (e) {
      await LogUtil.log('下载异常: $e, URL: $url', level: 'ERROR');
      throw Exception('下载出错: $e');
    }
  }

  // 获取系统内存
  Future<void> _getMemory() async {
    int bytes = SysInfo.getTotalPhysicalMemory();
    // 内存错误修正
    if (bytes > (1024 * 1024 * 1024 * 1024) && bytes % 16384 == 0) {
      bytes = bytes ~/ 16384;
    }
    final physicalMemory = bytes ~/ (1024 * 1024);
    setState(() {
      _mem = physicalMemory;
    });
  }

    // 游戏配置文件创建
  Future<void> _writeGameConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString('SelectedPath') ?? '';
    List<String> gameList = prefs.getStringList('Game_$_name') ?? [];
    // 默认配置
    List<String> defaultConfig = [
      '${_mem ~/ 2}',
      '0',
      '854',
      '480',
      'Vanilla',
      ''
    ];
    final key = 'Config_${_name}_${widget.name}';
    await prefs.setStringList(key, defaultConfig);
    gameList.add(widget.name);
    await prefs.setStringList('Game_$_name', gameList);
    LogUtil.log('已将 ${widget.name} 添加到游戏列表,当前列表: $gameList', level: 'INFO');
    setState(() {
      _writeConfig = true;
    });
  }

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _getMemory();
    _startDownload();
  }

  // 下载逻辑
  Future<void> _startDownload() async {
  final prefs = await SharedPreferences.getInstance();
  final selectedGamePath = prefs.getString('SelectedPath') ?? '';
  final gamePath = prefs.getString('Path_$selectedGamePath') ?? '';
  final versionPath = '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}';
  final gameJsonURL = replaceWithMirror(widget.url);
  try {
    await LogUtil.log('开始下载 ${widget.name} 版本', level: 'INFO');
    await _showNotification('开始下载', '正在下载 ${widget.name} 版本\n你可以将启动器置于后台,安装完成将有通知提醒');
    // 创建文件夹
    await _createGameDirectories();
    // 下载版本json
    try {
      await _downloadFile('$versionPath${Platform.pathSeparator}${widget.name}.json', gameJsonURL);
      setState(() {
        _downloadJson = true;
      });
    } catch (e) {
      await _showNotification('下载失败', '版本Json下载失败\n$e');
      setState(() {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载版本Json失败: $e')),
        );
      });
      return;
    }
    // 解析游戏Json
    await parseGameJson('$versionPath${Platform.pathSeparator}${widget.name}.json');
    // 下载资源索引文件
    if (assetIndexURL != null) {
      final assetIndexDir = '$gamePath${Platform.pathSeparator}assets${Platform.pathSeparator}indexes';
      final assetIndexPath = '$assetIndexDir${Platform.pathSeparator}$assetIndexId.json';
      try {
        await _downloadFile('$gamePath${Platform.pathSeparator}assets${Platform.pathSeparator}indexes${Platform.pathSeparator}$assetIndexId.json', assetIndexURL!);
        setState(() {
          _downloadAssetJson = true;
        });
      } catch (e) {
        setState(() {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('下载资产索引失败: $e')),
          );
        });
        return;
      }
      // 解析资产索引
      await parseAssetIndex(assetIndexPath);
      // 下载客户端
      try {
        await _downloadFile('$versionPath${Platform.pathSeparator}${widget.name}.jar', clientURL);
        setState(() {
          _downloadClient = true;
        });
      } catch (e) {
        setState(() {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('下载客户端失败: $e')),
          );
        });
        return;
      }
      // 下载库文件
      await _downloadLibraries();
      // 下载游戏资源
      await _downloadAssets();
      // 提取LWJGL本地库路径
      await _extractLwjglNativeLibrariesPath('$versionPath${Platform.pathSeparator}${widget.name}.json',gamePath);
      // 提取LWJGL Natives
      await _extractLwjglNatives();
      // 写入游戏配置文件
      await _writeGameConfig();
      // 完成通知
      await _showNotification('完成下载', '点击查看详细');
    }
  } catch (e) {
    setState(() {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发生错误: $e')),
      );
    });
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('正在下载原版游戏'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: ListTile(
              title: const Text('正在下载游戏Json'),
              subtitle: Text(_downloadJson ? '下载完成' : '下载中...'),
              trailing: _downloadJson
                ? const Icon(Icons.check)
                : const CircularProgressIndicator(),
            ),
          ),if (_downloadJson) ...[
            Card(
              child: ListTile(
                title: const Text('正在解析游戏Json'),
                subtitle: Text(_parseGameJson ? '解析完成' : '解析中...'),
                trailing: _parseGameJson
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            ),if (_parseAssetJson) ...[
              Card(
                child: ListTile(
                  title: const Text('正在下载资源Json'),
                  subtitle: Text(_downloadAssetJson ? '下载完成' : '下载中...'),
                  trailing: _downloadAssetJson
                    ? const Icon(Icons.check)
                    : const CircularProgressIndicator(),
                ),
              ),
            ]
          ],if (_downloadAssetJson) ...[
            Card(
              child: ListTile(
                title: const Text('正在解析资源Json'),
                subtitle: Text(_parseAssetJson ? '解析完成' : '解析中...'),
                trailing: _parseAssetJson
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            ),
          ],if (_parseAssetJson) ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('正在下载客户端'),
                    subtitle: Text(_downloadClient ? '下载完成' : '下载中... 已下载${(_progress * 100).toStringAsFixed(2)}%'),
                    trailing: _downloadClient
                      ? const Icon(Icons.check)
                      : const CircularProgressIndicator()
                  ),
                  if (!_downloadClient)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: LinearProgressIndicator(value: _progress),
                    ),
                ],
              )
            ),
          ],if (_downloadClient) ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('正在下载游戏库'),
                    subtitle: Text(_downloadLibrary ? '下载完成' : '下载中... 已下载${(_progress * 100).toStringAsFixed(2)}%'),
                    trailing: _downloadLibrary
                      ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
              if (!_downloadLibrary)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: LinearProgressIndicator(value: _progress),
                ),
              ],
            ),
            )
          ],if (_downloadLibrary) ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('正在下载游戏资源'),
                    subtitle: Text(_downloadAsset ? '下载完成' : '下载中... 已下载${(_progress * 100).toStringAsFixed(2)}%'),
                    trailing: _downloadAsset
                      ? const Icon(Icons.check)
                      : const CircularProgressIndicator(),
                  ),
                  if (!_downloadAsset)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: LinearProgressIndicator(value: _progress),
                    ),
                ],
              ),
            )
          ],if (_downloadAsset) ...[
            Card(
              child: ListTile(
                title: const Text('正在提取LWJGL路径'),
                subtitle: Text(_extractedLwjglNativesPath ? '提取完成' : '提取中...'),
                trailing: _extractedLwjglNativesPath
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            )
          ],if (_extractedLwjglNativesPath) ...[
            Card(
              child: ListTile(
                title: const Text('正在提取LWJGL'),
                subtitle: Text(_extractedLwjglNatives ? '提取完成' : '提取中...'),
                trailing: _extractedLwjglNatives
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            )],if (_extractedLwjglNatives) ...[
            Card(
              child: ListTile(
                title: const Text('正在写入配置文件'),
                subtitle: Text(_writeConfig ? '写入完成' : '写入中...'),
                trailing: _writeConfig
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            )
          ],
        ],
      ),
      floatingActionButton: _writeConfig
        ? FloatingActionButton(
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Icon(Icons.check),
          )
        : null,
    );
  }
}