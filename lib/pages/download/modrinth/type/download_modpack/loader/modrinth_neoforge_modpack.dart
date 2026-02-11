import 'package:flutter/material.dart';
import 'package:fml/function/dio_client.dart';
import 'package:fml/function/download.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:system_info2/system_info2.dart';

import 'package:fml/function/log.dart';
import 'package:fml/function/extract_natives.dart';

class NeoForgeModpackPage extends StatefulWidget {
  const NeoForgeModpackPage({super.key, required this.name, required this.url});

  final String name;
  final String url;

  @override
  NeoForgeModpackPageState createState() => NeoForgeModpackPageState();
}

class NeoForgeModpackPageState extends State<NeoForgeModpackPage> {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _downloadMrpack = false;
  bool _unzipMrpack = false;
  bool _parseMrpack = false;
  bool _downloadModsStatus = false;
  bool _downloadMinecraftJson = false;
  bool _parseGameJsonStatus = false;
  bool _downloadAssetJson = false;
  bool _parseAssetJson = false;
  bool _downloadClient = false;
  bool _downloadLibrary = false;
  bool _downloadAsset = false;
  bool _extractedLwjglNativesPath = false;
  bool _extractedLwjglNatives = false;
  bool _downloadNeoForge = false;
  bool _extractNeoForgeInstallerStatus = false;
  bool _parseNeoForgeInstallerJsonStatus = false;
  bool _downloadNeoForgeLibrary = false;
  bool _neoForgeInstalled = false;
  bool _copyOverrides = false;
  bool _writeConfig = false;

  double _progress = 0.0;

  String _neoforgeVersion = '';
  String _minecraftVersion = '';
  String _installerJson = '';
  String _name = '';
  String _neoForgeURL = '';

  int _totalMods = 0;
  int _mem = 1;

  List<String> _modsPath = [];
  List<String> _modsUrl = [];

  String? assetIndexURL;
  String? clientURL;
  String? assetIndexId;
  final List<String> _assetHash = [];
  List<String> librariesPath = [];
  List<String> librariesURL = [];
  List<String> lwjglNativeNames = [];
  List<String> lwjglNativePaths = [];
  List<String> neoForgeLibrariesPath = [];
  List<String> neoForgeLibrariesURL = [];

  // BMCLAPI 镜像
  String replaceWithMirror(String url) {
    return url
        .replaceAll('piston-meta.mojang.com', 'bmclapi2.bangbang93.com')
        .replaceAll('piston-data.mojang.com', 'bmclapi2.bangbang93.com')
        .replaceAll('launcher.mojang.com', 'bmclapi2.bangbang93.com')
        .replaceAll('launchermeta.mojang.com', 'bmclapi2.bangbang93.com')
        .replaceAll('libraries.minecraft.net', 'bmclapi2.bangbang93.com/maven')
        .replaceAll(
          'resources.download.minecraft.net',
          'bmclapi2.bangbang93.com/assets',
        )
        .replaceAll(
          'https://maven.neoforged.net/releases/net/neoforged/forge',
          'https://bmclapi2.bangbang93.com/maven/net/neoforged/forge',
        )
        .replaceAll(
          'https://maven.neoforged.net/releases/net/neoforged/neoforge',
          'https://bmclapi2.bangbang93.com/maven/net/neoforged/neoforge',
        );
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
      const InitializationSettings initializationSettings =
          InitializationSettings(
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
      const DarwinNotificationDetails darwinDetails =
          DarwinNotificationDetails();
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
    final directory = Directory(
      '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
      await LogUtil.log(
        '创建目录: $gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}',
        level: 'INFO',
      );
    }
  }

  // 解压Mrpack文件
  Future<void> _unzipMrpackFile(String versionPath) async {
    try {
      final mrpackFile = File(
        '$versionPath${Platform.pathSeparator}${widget.name}.mrpack',
      );
      final extractPath = '$versionPath${Platform.pathSeparator}mrpack';
      if (!await mrpackFile.exists()) {
        throw Exception('Mrpack文件不存在 ${mrpackFile.path}');
      }
      final bytes = await mrpackFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final directory = Directory(extractPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File(
            '$extractPath${Platform.pathSeparator}$filename',
          );
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(data);
          await LogUtil.log('解压文件: $filename', level: 'INFO');
        }
      }
      await LogUtil.log('Mrpack解压完成: $extractPath', level: 'INFO');
      setState(() {
        _unzipMrpack = true;
      });
    } catch (e) {
      await LogUtil.log('解压Mrpack失败: $e', level: 'ERROR');
      await _showNotification('解压失败', '无法解压Mrpack文件: $e');
      throw Exception('解压Mrpack失败: $e');
    }
  }

  // 解析Mrpack内容
  Future<void> _parseMrpackContent(String versionPath) async {
    try {
      final extractPath = '$versionPath${Platform.pathSeparator}mrpack';
      final indexFile = File(
        '$extractPath${Platform.pathSeparator}modrinth.index.json',
      );
      if (!await indexFile.exists()) {
        throw Exception('找不到modrinth.index.json文件');
      }
      final Map<String, dynamic> indexJson = jsonDecode(
        await indexFile.readAsString(),
      );
      if (indexJson.containsKey('dependencies')) {
        final dependencies = indexJson['dependencies'];
        _neoforgeVersion = dependencies['neoforge'] ?? '';
        _minecraftVersion = dependencies['minecraft'] ?? '';
        _neoForgeURL =
            'https://bmclapi2.bangbang93.com/maven/net/neoforged/neoforge/$_neoforgeVersion/neoforge-$_neoforgeVersion-installer.jar';
        await LogUtil.log('检测到neoforge版本: $_neoforgeVersion', level: 'INFO');
        await LogUtil.log('检测到Minecraft版本: $_minecraftVersion', level: 'INFO');
      }
      if (indexJson.containsKey('files') && indexJson['files'] is List) {
        final List<dynamic> filesList = indexJson['files'];
        _totalMods = filesList.length;
        for (var fileInfo in filesList) {
          if (fileInfo['path'] != null) {
            _modsPath.add(fileInfo['path']);
          }
          if (fileInfo['downloads'] != null &&
              fileInfo['downloads'] is List &&
              fileInfo['downloads'].isNotEmpty) {
            _modsUrl.add(fileInfo['downloads'][0]);
          } else {
            _modsUrl.add('');
          }
        }
        await LogUtil.log('解析了 ${_modsPath.length} 个文件路径和下载URL', level: 'INFO');
      }
      setState(() {
        _parseMrpack = true;
      });
    } catch (e) {
      await LogUtil.log('解析Mrpack内容失败: $e', level: 'ERROR');
      await _showNotification('解析失败', '无法解析Mrpack内容: $e');
      throw Exception('解析Mrpack内容失败: $e');
    }
  }

  // 下载和处理模组文件
  Future<void> _downloadMods(String versionPath) async {
    try {
      setState(() {
        _downloadModsStatus = false;
        _progress = 0.0;
      });
      final extractPath = '$versionPath${Platform.pathSeparator}mrpack';
      await LogUtil.log('开始处理$_totalMods 个模组文件', level: 'INFO');
      final modsDir = Directory('$versionPath${Platform.pathSeparator}mods');
      if (!await modsDir.exists()) {
        await modsDir.create(recursive: true);
      }
      final resourcepacksDir = Directory(
        '$versionPath${Platform.pathSeparator}resourcepacks',
      );
      if (!await resourcepacksDir.exists()) {
        await resourcepacksDir.create(recursive: true);
      }
      List<Map<String, String>> downloadTasks = [];
      int copiedCount = 0;
      for (int i = 0; i < _modsPath.length; i++) {
        final path = _modsPath[i];
        final url = i < _modsUrl.length ? _modsUrl[i] : '';
        final String fileName = path.split('/').last;
        String targetPath;
        if (path.startsWith('mods/')) {
          targetPath =
              '$versionPath${Platform.pathSeparator}mods${Platform.pathSeparator}$fileName';
        } else if (path.startsWith('resourcepacks/')) {
          targetPath =
              '$versionPath${Platform.pathSeparator}resourcepacks${Platform.pathSeparator}$fileName';
        } else {
          final parts = path.split('/');
          if (parts.length > 1) {
            final dirPath =
                '$versionPath${Platform.pathSeparator}${parts.sublist(0, parts.length - 1).join(Platform.pathSeparator)}';
            final dirObj = Directory(dirPath);
            if (!await dirObj.exists()) {
              await dirObj.create(recursive: true);
            }
            targetPath = '$dirPath${Platform.pathSeparator}$fileName';
          } else {
            targetPath = '$versionPath${Platform.pathSeparator}$fileName';
          }
        }
        final targetFile = File(targetPath);
        if (!await targetFile.parent.exists()) {
          await targetFile.parent.create(recursive: true);
        }
        // 优先从本地复制
        final String localFilePath =
            '$extractPath${Platform.pathSeparator}${path.replaceAll('/', Platform.pathSeparator)}';
        final File localFile = File(localFilePath);
        if (await localFile.exists()) {
          try {
            await localFile.copy(targetPath);
            copiedCount++;
            await LogUtil.log('复制文件 ($copiedCount): $fileName', level: 'INFO');
          } catch (e) {
            await LogUtil.log('复制文件失败: $fileName - $e', level: 'ERROR');
            if (url.isNotEmpty) {
              downloadTasks.add({'url': url, 'path': targetPath});
            }
          }
        } else if (url.isNotEmpty) {
          downloadTasks.add({'url': url, 'path': targetPath});
        } else {
          await LogUtil.log(
            '无法处理文件: $fileName - 本地不存在且下载URL为空',
            level: 'ERROR',
          );
        }
      }
      await LogUtil.log(
        '本地复制完成: $copiedCount 个文件 需要下载 ${downloadTasks.length} 个文件',
        level: 'INFO',
      );
      // 多线程下载剩余文件
      if (downloadTasks.isNotEmpty) {
        final downloadResult = await DownloadUtils.batchDownload(
          tasks: downloadTasks,
          fileType: '模组文件',
          onProgress: (progress) {
            setState(() {
              _progress =
                  (copiedCount + progress * downloadTasks.length) / _totalMods;
            });
          },
        );
        await LogUtil.log(
          '下载完成: 总数=${downloadResult.totalCount}, 成功=${downloadResult.completedCount}, 失败=${downloadResult.failedList.length}',
          level: 'INFO',
        );
      }
      setState(() {
        _downloadModsStatus = true;
        _progress = 1.0;
      });
      await LogUtil.log('所有模组文件处理完成, 状态已更新', level: 'INFO');
    } catch (e) {
      await LogUtil.log('下载模组失败: $e', level: 'ERROR');
      await _showNotification('模组下载失败', '无法完成模组下载: $e');
      throw Exception('下载模组失败: $e');
    }
  }

  // 获取游戏 Json
  Future<void> _saveMinecraftJson(String versionPath) async {
    final options = Options(responseType: ResponseType.plain);
    int retry = 0;
    while (true) {
      try {
        await LogUtil.log('请求版本清单 (尝试第 ${retry + 1} 次)', level: 'INFO');
        final response = await DioClient().dio.get(
          'https://bmclapi2.bangbang93.com/mc/game/version_manifest.json',
          options: options,
        );
        if (response.statusCode == 200) {
          await LogUtil.log('成功获取版本清单', level: 'INFO');
          dynamic parsedData;
          if (response.data is String) {
            parsedData = jsonDecode(response.data);
          } else {
            parsedData = response.data;
          }
          if (parsedData != null && parsedData.containsKey('versions')) {
            final versions = parsedData['versions'] as List<dynamic>;
            for (var v in versions) {
              if (v is Map && v['id'] == _minecraftVersion) {
                final url = v['url'];
                if (url != null) {
                  try {
                    final resp = await DioClient().dio.get(
                      url,
                      options: Options(responseType: ResponseType.plain),
                    );
                    if (resp.statusCode == 200) {
                      final filePath =
                          '$versionPath${Platform.pathSeparator}${widget.name}.json';
                      await File(filePath).writeAsString(
                        resp.data is String ? resp.data : jsonEncode(resp.data),
                      );
                      await LogUtil.log(
                        '已保存游戏 JSON 到: $filePath',
                        level: 'INFO',
                      );
                      setState(() {
                        _downloadMinecraftJson = true;
                      });
                    }
                  } catch (e) {
                    await LogUtil.log('下载游戏 JSON 失败: $e', level: 'ERROR');
                  }
                }
                break;
              }
            }
          }
          return;
        } else {
          throw Exception('HTTP ${response.statusCode}');
        }
      } catch (e) {
        retry++;
        final delayMs = (300 * (1 << ((retry - 1).clamp(0, 8)))).clamp(
          300,
          30000,
        );
        await LogUtil.log(
          '请求版本清单失败 (第 $retry 次): $e —— ${delayMs}ms 后重试',
          level: 'WARNING',
        );
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
  }

  // 游戏Json解析
  Future<void> _parseGameJson(String jsonFilePath) async {
    try {
      final file = File(jsonFilePath);
      if (!file.existsSync()) {
        throw Exception('JSON文件不存在 $jsonFilePath');
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
        await LogUtil.log('找到 ${librariesPath.length} 个库文件路径', level: 'INFO');
        await LogUtil.log('找到 ${librariesURL.length} 个库文件URL', level: 'INFO');
      }
      setState(() {
        _parseGameJsonStatus = true;
      });
    } catch (e) {
      await _showNotification('解析JSON失败', e.toString());
      await LogUtil.log('解析JSON失败: $e', level: 'ERROR');
    }
  }

  // 解析Assset JSON
  Future<void> _parseAssetIndex(String assetIndexPath) async {
    try {
      final file = File(assetIndexPath);
      if (!file.existsSync()) {
        throw Exception('资产索引文件不存在 $assetIndexPath');
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
      await LogUtil.log('已解析${_assetHash.length} 个资产哈希', level: 'INFO');
      setState(() {
        _parseAssetJson = true;
      });
    } catch (e) {
      await _showNotification('解析资产索引失败', e.toString());
      await LogUtil.log('解析资产索引失败: $e', level: 'ERROR');
    }
  }

  // 下载库文件
  Future<void> _downloadLibraries() async {
    if (librariesURL.isEmpty || librariesPath.isEmpty) {
      await _showNotification('库文件列表为空, 无法下载库文件', '');
      await LogUtil.log('库文件列表为空，无法下载库文件', level: 'ERROR');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final selectedGamePath = prefs.getString('SelectedPath') ?? '';
    final gamePath = prefs.getString('Path_$selectedGamePath') ?? '';
    List<Map<String, String>> downloadTasks = [];
    for (int i = 0; i < librariesURL.length; i++) {
      final url = librariesURL[i];
      final relativePath = librariesPath[i];
      final fullPath =
          '$gamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}$relativePath';
      final file = File(fullPath);
      if (!file.existsSync()) {
        downloadTasks.add({'url': url, 'path': fullPath});
      }
    }
    final totalLibraries = downloadTasks.length;
    if (totalLibraries == 0) {
      await LogUtil.log('所有库文件已存在，无需下载', level: 'INFO');
      setState(() {
        _downloadLibrary = true;
      });
      return;
    }
    await LogUtil.log('开始下载 $totalLibraries 个库文件', level: 'INFO');
    await DownloadUtils.batchDownload(
      tasks: downloadTasks,
      onProgress: (progress) {
        setState(() {
          _progress = progress;
        });
      },
    );
    setState(() {
      _downloadLibrary = true;
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
      final assetDir =
          '$gamePath${Platform.pathSeparator}assets${Platform.pathSeparator}objects${Platform.pathSeparator}$hashPrefix';
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
    final totalAssets = downloadTasks.length;
    if (totalAssets == 0) {
      await LogUtil.log('所有资源文件已存在，无需下载', level: 'INFO');
      setState(() {
        _downloadAsset = true;
      });
      return;
    }
    await LogUtil.log('需要下载 $totalAssets 个资源文件', level: 'INFO');
    await DownloadUtils.batchDownload(
      tasks: downloadTasks,
      onProgress: (progress) {
        setState(() {
          _progress = progress;
        });
      },
    );
    setState(() {
      _downloadAsset = true;
    });
  }

  // 提取LWJGL本地库文件的名称和路径
  Future<void> extractLwjglNativeLibrariesPath(
    String jsonFilePath,
    String gamePath,
  ) async {
    final namesList = <String>[];
    final pathsList = <String>[];
    final file = File(jsonFilePath);
    if (!await file.exists()) {
      await LogUtil.log('版本JSON文件不存在 $jsonFilePath', level: 'ERROR');
      await _showNotification('版本JSON文件不存在', jsonFilePath);
      setState(() {
        lwjglNativeNames = namesList;
        lwjglNativePaths = pathsList;
        _extractedLwjglNativesPath = true;
      });
      return;
    }
    late final dynamic root;
    try {
      root = jsonDecode(await file.readAsString());
    } catch (e) {
      await LogUtil.log('JSON 解析失败: $e', level: 'ERROR');
      await _showNotification('JSON 解析失败', e.toString());
      setState(() {
        lwjglNativeNames = namesList;
        lwjglNativePaths = pathsList;
        _extractedLwjglNativesPath = true;
      });
      return;
    }
    final libs = root is Map ? root['libraries'] : null;
    if (libs is! List) {
      await LogUtil.log('JSON中没有libraries字段或格式错误', level: 'ERROR');
      await _showNotification('JSON中没有libraries字段或格式错误', jsonFilePath);
      setState(() {
        lwjglNativeNames = namesList;
        lwjglNativePaths = pathsList;
        _extractedLwjglNativesPath = true;
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
      // 检查是否为所需的LWJGL本地库文件
      if ((fileName.startsWith('lwjgl-') && fileName.contains('-natives-')) ||
          (fileName.startsWith('lwjgl-freetype-') &&
              fileName.contains('-natives-')) ||
          (fileName.startsWith('lwjgl-glfw-') &&
              fileName.contains('-natives-')) ||
          (fileName.startsWith('lwjgl-jemalloc-') &&
              fileName.contains('-natives-')) ||
          (fileName.startsWith('lwjgl-openal-') &&
              fileName.contains('-natives-')) ||
          (fileName.startsWith('lwjgl-stb-') &&
              fileName.contains('-natives-')) ||
          fileName.startsWith('lwjgl-tinyfd')) {
        namesList.add(fileName);
        String nativePath = path.replaceAll('/', Platform.pathSeparator);
        final fullPath =
            ('$gamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}$nativePath');
        pathsList.add(fullPath);
        await LogUtil.log(
          '找到LWJGL本地库文件 $fileName, 路径: $fullPath',
          level: 'INFO',
        );
      }
    }
    await LogUtil.log('总共找到${namesList.length}个LWJGL本地库文件', level: 'INFO');
    setState(() {
      lwjglNativeNames = namesList;
      lwjglNativePaths = pathsList;
      _extractedLwjglNativesPath = true;
    });
  }

  // 提取LWJGL Natives
  Future<void> _extractLwjglNatives() async {
    if (lwjglNativePaths.isEmpty || lwjglNativeNames.isEmpty) {
      await LogUtil.log('没有找到LWJGL本地库, 跳过提取', level: 'WARNING');
      setState(() {
        _extractedLwjglNativesPath = true;
      });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final selectedGamePath = prefs.getString('SelectedPath') ?? '';
    final gamePath = prefs.getString('Path_$selectedGamePath') ?? '';
    final nativesDir =
        '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}${Platform.pathSeparator}natives';
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
        final jarDir = fullPath.substring(
          0,
          fullPath.lastIndexOf(Platform.pathSeparator),
        );
        await LogUtil.log(
          '提取: $fileName 从 $jarDir 到 $nativesDir',
          level: 'INFO',
        );
        // 调用extractNatives函数提取本地库
        final extracted = await extractNatives(jarDir, fileName, nativesDir);
        if (extracted.isNotEmpty) {
          successCount++;
          extractedFiles.addAll(extracted);
          await LogUtil.log(
            '成功提取 $fileName 共 ${extracted.length} 个文件',
            level: 'INFO',
          );
        }
      } catch (e) {
        await LogUtil.log('提取 $fileName 时出现错误 $e', level: 'ERROR');
      }
    }
    await LogUtil.log(
      '完成LWJGL本地库提取 共处理${lwjglNativePaths.length} 个文件 成功: $successCount',
      level: 'INFO',
    );
    await LogUtil.log('提取的文件 ${extractedFiles.join(', ')}', level: 'INFO');
    setState(() {
      _extractedLwjglNatives = true;
    });
  }

  // 提取NeoForge
  Future<void> _extractNeoForgeInstaller() async {
    try {
      // 读取JAR文件
      final prefs = await SharedPreferences.getInstance();
      final selectedGamePath = prefs.getString('SelectedPath') ?? '';
      final gamePath = prefs.getString('Path_$selectedGamePath') ?? '';
      final neoForgePath =
          '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}${Platform.pathSeparator}neoforge-installer.jar';
      final bytes = await File(neoForgePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      // 提取install_profile.json文件
      for (final file in archive) {
        if (file.name == 'install_profile.json') {
          final content = file.content as List<int>;
          _installerJson = utf8.decode(content);
          // 保存到文件
          final jsonFile = File(
            '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}${Platform.pathSeparator}install_profile.json',
          );
          await jsonFile.writeAsBytes(content);
          break;
        }
      }
      if (_installerJson.isEmpty) {
        throw Exception('无法从安装器中提取install_profile.json');
      }
    } catch (e) {
      throw Exception('提取NeoForge安装器失败 $e');
    }
    setState(() {
      _extractNeoForgeInstallerStatus = true;
    });
  }

  // 解析NeoForge安装器JSON
  Future<void> _parseNeoForgeInstallerJson() async {
    neoForgeLibrariesURL.clear();
    neoForgeLibrariesPath.clear();
    if (_installerJson.isEmpty) return;
    try {
      final json = jsonDecode(_installerJson);
      if (json['libraries'] != null && json['libraries'] is List) {
        await LogUtil.log('找到NeoForge libraries,开始解析...', level: 'INFO');
        for (var lib in json['libraries']) {
          if (lib['downloads'] != null &&
              lib['downloads']['artifact'] != null) {
            final artifact = lib['downloads']['artifact'];
            if (artifact['path'] != null) {
              neoForgeLibrariesPath.add(artifact['path']);
            }
            if (artifact['url'] != null) {
              String url = artifact['url'];
              url = url.replaceAll(
                'https://maven.neoforged.net/releases/net',
                'https://bmclapi2.bangbang93.com/maven/net',
              );
              neoForgeLibrariesURL.add(url);
            }
          } else if (lib['name'] != null) {
            final String mavenCoords = lib['name'];
            try {
              final parts = mavenCoords.split(':');
              if (parts.length >= 3) {
                final group = parts[0].replaceAll('.', '/');
                final artifact = parts[1];
                final version = parts[2];
                final path = '$group/$artifact/$version/$artifact-$version.jar';
                neoForgeLibrariesPath.add(path);
                final url = 'https://bmclapi2.bangbang93.com/maven/$path';
                neoForgeLibrariesURL.add(url);
              }
            } catch (e) {
              await LogUtil.log(
                '解析Maven坐标失败: $mavenCoords, 错误: $e',
                level: 'ERROR',
              );
            }
          }
        }
        librariesPath.addAll(neoForgeLibrariesPath);
        librariesURL.addAll(neoForgeLibrariesURL);
        await LogUtil.log(
          '成功解析NeoForge libraries: ${neoForgeLibrariesURL.length}个',
          level: 'INFO',
        );
      } else {
        await LogUtil.log('未找到NeoForge libraries或格式不正确', level: 'ERROR');
      }
    } catch (e) {
      await LogUtil.log('解析NeoForge安装器JSON失败: $e', level: 'ERROR');
    }
    setState(() {
      _parseNeoForgeInstallerJsonStatus = true;
    });
  }

  // 下载NeoForge库
  Future<void> _downloadNeoForgeLibraries() async {
    if (neoForgeLibrariesURL.isEmpty || neoForgeLibrariesPath.isEmpty) {
      await LogUtil.log('NeoForge库文件列表为空', level: 'ERROR');
      await _showNotification('下载失败', 'NeoForge库文件列表为空');
      setState(() {
        _downloadNeoForgeLibrary = true;
      });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final selectedGamePath = prefs.getString('SelectedPath') ?? '';
    final gamePath = prefs.getString('Path_$selectedGamePath') ?? '';
    List<Map<String, String>> downloadTasks = [];
    final libraryDir = Directory('$gamePath${Platform.pathSeparator}libraries');
    if (!await libraryDir.exists()) {
      await libraryDir.create(recursive: true);
    }
    for (int i = 0; i < neoForgeLibrariesURL.length; i++) {
      final url = neoForgeLibrariesURL[i];
      final relativePath = neoForgeLibrariesPath[i];
      final fullPath =
          '$gamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}$relativePath';
      final file = File(fullPath);
      if (!file.existsSync()) {
        downloadTasks.add({'url': url, 'path': fullPath});
      }
    }
    final totalLibraries = downloadTasks.length;
    if (totalLibraries == 0) {
      await LogUtil.log('所有NeoForge库文件已存在,无需下载', level: 'INFO');
      setState(() {
        _downloadNeoForgeLibrary = true;
      });
      return;
    }
    await LogUtil.log('开始下载 $totalLibraries 个NeoForge库文件', level: 'INFO');
    await DownloadUtils.batchDownload(
      tasks: downloadTasks,
      onProgress: (progress) {
        setState(() {
          _progress = progress;
        });
      },
    );
    setState(() {
      _downloadNeoForgeLibrary = true;
    });
  }

  // 执行 NeoForge 安装器
  Future<void> _executeNeoForgeInstaller() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedGamePath = prefs.getString('SelectedPath') ?? '';
    final gamePath = prefs.getString('Path_$selectedGamePath') ?? '';
    final installerPath =
        '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}${Platform.pathSeparator}neoforge-installer.jar';
    final neoForgeJson =
        '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}neoforge-$_neoforgeVersion${Platform.pathSeparator}neoforge-$_neoforgeVersion.json';
    await LogUtil.log('开始执行NeoForge安装器 $installerPath', level: 'INFO');
    final result = await Process.run('java', [
      '-jar',
      installerPath,
      '--installClient',
      gamePath,
    ]);
    if (result.stderr.toString().isNotEmpty) {
      for (var line in result.stderr.toString().split('\n')) {
        if (line.trim().isNotEmpty) {
          await LogUtil.log('[NEOFORGE INSTALLER] $line', level: 'ERROR');
        }
      }
    }
    final code = result.exitCode;
    await LogUtil.log('NeoForge安装器退出码: $code', level: 'INFO');
    if (code != 0) {
      throw Exception('NeoForge安装器执行失败 退出码: $code');
    }
    await LogUtil.log('NeoForge安装器执行成功', level: 'INFO');
    await LogUtil.log(
      '移动$neoForgeJson 配置文件到 $gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}${Platform.pathSeparator}NeoForge.json',
      level: 'INFO',
    );
    await _moveFile(
      neoForgeJson,
      '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}${Platform.pathSeparator}NeoForge.json',
    );
    setState(() {
      _neoForgeInstalled = true;
    });
  }

  // 移动文件
  Future<void> _moveFile(String sourcePath, String destinationPath) async {
    try {
      final sourceFile = File(sourcePath);
      // 确保源文件存在
      if (!await sourceFile.exists()) {
        throw Exception('源文件不存在: $sourcePath');
      }
      final destinationDir = Directory(
        destinationPath.substring(
          0,
          destinationPath.lastIndexOf(Platform.pathSeparator),
        ),
      );
      if (!await destinationDir.exists()) {
        await destinationDir.create(recursive: true);
      }
      // 移动文件
      await sourceFile.rename(destinationPath);
      await LogUtil.log('文件已成功移动到: $destinationPath', level: 'INFO');
    } catch (e) {
      await LogUtil.log('移动文件时发生错误: $e', level: 'ERROR');
      await _showNotification('移动文件时发生错误', e.toString());
    }
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
        },
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

  // 复制整合包内 overrides 内容
  Future<void> _copyOverridesContent(String versionPath) async {
    try {
      final overridesDir = Directory(
        '$versionPath${Platform.pathSeparator}mrpack${Platform.pathSeparator}overrides',
      );
      if (!await overridesDir.exists()) {
        await LogUtil.log('overrides文件夹不存在,跳过复制', level: 'INFO');
        return;
      }
      await LogUtil.log('开始复制overrides文件夹内容到版本文件夹', level: 'INFO');
      int copiedFiles = 0;
      int copiedDirs = 0;
      Future<void> copyDirectory(
        Directory source,
        Directory destination,
      ) async {
        if (!await destination.exists()) {
          await destination.create(recursive: true);
          copiedDirs++;
        }
        await for (final entity in source.list(
          recursive: false,
          followLinks: false,
        )) {
          final String relativePath = entity.path.substring(source.path.length);
          final String destinationPath = '${destination.path}$relativePath';
          if (entity is File) {
            await entity.copy(destinationPath);
            copiedFiles++;
            if (copiedFiles % 10 == 0) {
              await LogUtil.log('已复制 $copiedFiles 个文件', level: 'INFO');
            }
          } else if (entity is Directory) {
            await copyDirectory(entity, Directory(destinationPath));
          }
        }
      }

      await copyDirectory(overridesDir, Directory(versionPath));
      await LogUtil.log(
        'overrides内容复制完成,共复制 $copiedFiles 个文件和 $copiedDirs 个目录',
        level: 'INFO',
      );
      setState(() {
        _copyOverrides = true;
      });
    } catch (e) {
      await LogUtil.log('复制overrides内容失败: $e', level: 'ERROR');
      await _showNotification('复制失败', '无法复制overrides内容: $e');
      throw Exception('复制overrides内容失败: $e');
    }
  }

  // 获取系统内存
  void _getMemory() {
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
      'NeoForge',
      '',
    ];
    final key = 'Config_${_name}_${widget.name}';
    await prefs.setStringList(key, defaultConfig);
    gameList.add(widget.name);
    await prefs.setStringList('Game_$_name', gameList);
    await LogUtil.log(
      '已将 ${widget.name} 添加到游戏列表, 当前列表: $gameList',
      level: 'INFO',
    );
    setState(() {
      _writeConfig = true;
    });
  }

  // 下载逻辑
  Future<void> _startDownload() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedGamePath = prefs.getString('SelectedPath') ?? '';
    final gamePath = prefs.getString('Path_$selectedGamePath') ?? '';
    final versionPath =
        '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}';
    try {
      await LogUtil.log('正在下载整合包 ${widget.name}', level: 'INFO');
      await _showNotification(
        '开始下载',
        '正在下载 ${widget.name} \n你可以将启动器置于后台, 安装完成将有通知提醒',
      );
      // 创建文件夹
      await _createGameDirectories();
      // 下载整合包信息
      try {
        await _downloadFile(
          '$versionPath${Platform.pathSeparator}${widget.name}.mrpack',
          widget.url,
        );
        setState(() {
          _downloadMrpack = true;
        });
      } catch (e) {
        setState(() {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('下载整合包信息失败: $e')));
        });
        return;
      }
      // 解压整合包信息
      await _unzipMrpackFile(versionPath);
      // 解析整合包内容
      await _parseMrpackContent(versionPath);
      // 下载模组文件
      await _downloadMods(versionPath);
      // 保存Minecraft Json
      await _saveMinecraftJson(versionPath);
      // 解析游戏Json
      await _parseGameJson(
        '$versionPath${Platform.pathSeparator}${widget.name}.json',
      );
      // 下载资产索引文件
      if (assetIndexURL != null) {
        final assetIndexDir =
            '$gamePath${Platform.pathSeparator}assets${Platform.pathSeparator}indexes';
        final assetIndexPath =
            '$assetIndexDir${Platform.pathSeparator}$assetIndexId.json';
        try {
          await _downloadFile(
            '$gamePath${Platform.pathSeparator}assets${Platform.pathSeparator}indexes${Platform.pathSeparator}$assetIndexId.json',
            assetIndexURL!,
          );
          setState(() {
            _downloadAssetJson = true;
          });
        } catch (e) {
          setState(() {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('下载资产索引失败: $e')));
          });
          return;
        }
        // 解析资产索引文件
        await _parseAssetIndex(assetIndexPath);
        // 下载客户端文件
        try {
          await _downloadFile(
            '$versionPath${Platform.pathSeparator}${widget.name}.jar',
            clientURL,
          );
          setState(() {
            _downloadClient = true;
          });
        } catch (e) {
          setState(() {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('下载客户端失败: $e')));
          });
          return;
        }
        // 下载库文件
        await _downloadLibraries();
        // 下载资源文件
        await _downloadAssets();
        // 提取LWJGL本地库路径
        await extractLwjglNativeLibrariesPath(
          '$versionPath${Platform.pathSeparator}${widget.name}.json',
          gamePath,
        );
        // 提取LWJGL Natives
        await _extractLwjglNatives();
        // 下载NeoForge安装器
        LogUtil.log('开始下载 $versionPath, $_neoForgeURL', level: 'INFO');
        try {
          await _downloadFile(
            '$versionPath${Platform.pathSeparator}neoforge-installer.jar',
            _neoForgeURL,
          );
          setState(() {
            _downloadNeoForge = true;
          });
        } catch (e) {
          setState(() {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('下载NeoForge失败: $e')));
          });
          return;
        }
        // 提取NeoForge安装器
        await _extractNeoForgeInstaller();
        // 解析NeoForge安装器JSON
        await _parseNeoForgeInstallerJson();
        // 下载NeoForge库文件
        await _downloadNeoForgeLibraries();
        // 执行NeoForge安装器
        await _executeNeoForgeInstaller();
        // 复制整合包内 overrides 内容
        await _copyOverridesContent(versionPath);
        // 写入游戏配置文件
        await _writeGameConfig();
        // 完成通知
        await _showNotification('完成下载', '点击查看详细');
      }
    } catch (e) {
      setState(() {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('发生错误: $e')));
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _getMemory();
    _startDownload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('下载整合包 ${widget.name}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: ListTile(
              title: const Text('正在下载整合包信息'),
              subtitle: Text(_downloadMrpack ? '下载完成' : '下载中...'),
              trailing: _downloadMrpack
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
            ),
          ),
          if (_downloadMrpack) ...[
            Card(
              child: ListTile(
                title: const Text('正在解压整合包信息'),
                subtitle: Text(_unzipMrpack ? '解压完成' : '解压中...'),
                trailing: _unzipMrpack
                    ? const Icon(Icons.check)
                    : const CircularProgressIndicator(),
              ),
            ),
          ],
          if (_unzipMrpack) ...[
            Card(
              child: ListTile(
                title: const Text('正在解析整合包信息'),
                subtitle: Text(_parseMrpack ? '解析完成' : '解析中...'),
                trailing: _parseMrpack
                    ? const Icon(Icons.check)
                    : const CircularProgressIndicator(),
              ),
            ),
          ],
          if (_unzipMrpack) ...[
            Card(
              child: ListTile(
                title: const Text('正在解析整合包信息'),
                subtitle: Text(_parseMrpack ? '解析完成' : '解析中...'),
                trailing: _parseMrpack
                    ? const Icon(Icons.check)
                    : const CircularProgressIndicator(),
              ),
            ),
          ],
          if (_parseMrpack) ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('正在下载模组文件'),
                    subtitle: Text(
                      _downloadModsStatus
                          ? '下载完成'
                          : '下载中... 已下载${(_progress * 100).toStringAsFixed(2)}%',
                    ),
                    trailing: _downloadModsStatus
                        ? const Icon(Icons.check)
                        : const CircularProgressIndicator(),
                  ),
                  if (!_downloadModsStatus)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: LinearProgressIndicator(value: _progress),
                    ),
                ],
              ),
            ),
          ],
          if (_downloadModsStatus) ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('正在获取游戏Json'),
                    subtitle: Text(_downloadMinecraftJson ? '获取完成' : '获取中...'),
                    trailing: _downloadMinecraftJson
                        ? const Icon(Icons.check)
                        : const CircularProgressIndicator(),
                  ),
                ],
              ),
            ),
          ],
          if (_downloadMinecraftJson) ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('正在解析游戏Json'),
                    subtitle: Text(_parseGameJsonStatus ? '解析完成' : '解析中...'),
                    trailing: _parseGameJsonStatus
                        ? const Icon(Icons.check)
                        : const CircularProgressIndicator(),
                  ),
                ],
              ),
            ),
          ],
          if (_parseGameJsonStatus) ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('正在获取资源Json'),
                    subtitle: Text(_downloadAssetJson ? '获取完成' : '获取中...'),
                    trailing: _downloadAssetJson
                        ? const Icon(Icons.check)
                        : const CircularProgressIndicator(),
                  ),
                ],
              ),
            ),
          ],
          if (_downloadAssetJson) ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('正在解析资源Json'),
                    subtitle: Text(_parseAssetJson ? '解析完成' : '解析中...'),
                    trailing: _parseAssetJson
                        ? const Icon(Icons.check)
                        : const CircularProgressIndicator(),
                  ),
                ],
              ),
            ),
          ],
          if (_parseAssetJson) ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('正在下载客户端'),
                    subtitle: Text(
                      _downloadClient
                          ? '下载完成'
                          : '下载中... 已下载${(_progress * 100).toStringAsFixed(2)}%',
                    ),
                    trailing: _downloadClient
                        ? const Icon(Icons.check)
                        : const CircularProgressIndicator(),
                  ),
                  if (!_downloadClient)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: LinearProgressIndicator(value: _progress),
                    ),
                ],
              ),
            ),
          ],
          if (_downloadClient) ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('正在下载游戏库'),
                    subtitle: Text(
                      _downloadLibrary
                          ? '下载完成'
                          : '下载中... 已下载${(_progress * 100).toStringAsFixed(2)}%',
                    ),
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
            ),
          ],
          if (_downloadLibrary) ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('正在下载游戏资源'),
                    subtitle: Text(
                      _downloadAsset
                          ? '下载完成'
                          : '下载中... 已下载${(_progress * 100).toStringAsFixed(2)}%',
                    ),
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
            ),
          ],
          if (_downloadAsset) ...[
            Card(
              child: ListTile(
                title: const Text('正在提取LWJGL路径'),
                subtitle: Text(_extractedLwjglNativesPath ? '提取完成' : '提取中...'),
                trailing: _extractedLwjglNativesPath
                    ? const Icon(Icons.check)
                    : const CircularProgressIndicator(),
              ),
            ),
          ],
          if (_extractedLwjglNativesPath) ...[
            Card(
              child: ListTile(
                title: const Text('正在提取LWJGL'),
                subtitle: Text(_extractedLwjglNatives ? '提取完成' : '提取中...'),
                trailing: _extractedLwjglNatives
                    ? const Icon(Icons.check)
                    : const CircularProgressIndicator(),
              ),
            ),
          ],
          if (_extractedLwjglNatives) ...[
            Card(
              child: ListTile(
                title: const Text('正在下载NeoForge'),
                subtitle: Text(_downloadNeoForge ? '下载完成' : '下载中...'),
                trailing: _downloadNeoForge
                    ? const Icon(Icons.check)
                    : const CircularProgressIndicator(),
              ),
            ),
          ],
          if (_downloadNeoForge) ...[
            Card(
              child: ListTile(
                title: const Text('正在解压NeoForge安装列表'),
                subtitle: Text(
                  _extractNeoForgeInstallerStatus ? '解压完成' : '解压中...',
                ),
                trailing: _extractNeoForgeInstallerStatus
                    ? const Icon(Icons.check)
                    : const CircularProgressIndicator(),
              ),
            ),
          ],
          if (_extractNeoForgeInstallerStatus) ...[
            Card(
              child: ListTile(
                title: const Text('正在解析NeoForge Json'),
                subtitle: Text(
                  _parseNeoForgeInstallerJsonStatus ? '解析完成' : '解析中...',
                ),
                trailing: _parseNeoForgeInstallerJsonStatus
                    ? const Icon(Icons.check)
                    : const CircularProgressIndicator(),
              ),
            ),
          ],
          if (_parseNeoForgeInstallerJsonStatus) ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('正在下载NeoForge库文件'),
                    subtitle: Text(
                      _downloadNeoForgeLibrary
                          ? '下载完成'
                          : '下载中... 已下载 ${(_progress * 100).toStringAsFixed(2)}%',
                    ),
                    trailing: _downloadNeoForgeLibrary
                        ? const Icon(Icons.check)
                        : const CircularProgressIndicator(),
                  ),
                  if (!_downloadNeoForgeLibrary)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: LinearProgressIndicator(value: _progress),
                    ),
                ],
              ),
            ),
          ],
          if (_downloadNeoForgeLibrary) ...[
            Card(
              child: ListTile(
                title: const Text('正在安装NeoForge'),
                subtitle: Text(_neoForgeInstalled ? '安装完成' : '安装中...'),
                trailing: _neoForgeInstalled
                    ? const Icon(Icons.check)
                    : const CircularProgressIndicator(),
              ),
            ),
          ],
          if (_neoForgeInstalled) ...[
            Card(
              child: ListTile(
                title: const Text('正在复制整合包文件'),
                subtitle: Text(_copyOverrides ? '复制完成' : '复制中...'),
                trailing: _copyOverrides
                    ? const Icon(Icons.check)
                    : const CircularProgressIndicator(),
              ),
            ),
          ],
          if (_copyOverrides) ...[
            Card(
              child: ListTile(
                title: const Text('正在写入配置文件'),
                subtitle: Text(_writeConfig ? '写入完成' : '写入中...'),
                trailing: _writeConfig
                    ? const Icon(Icons.check)
                    : const CircularProgressIndicator(),
              ),
            ),
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
