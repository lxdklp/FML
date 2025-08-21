import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'dart:convert';
import 'package:system_info2/system_info2.dart';

import 'package:fml/function/download.dart';
import 'package:fml/function/extract_natives.dart';
import 'package:fml/function/log.dart';

class DownloadVanillaPage extends StatefulWidget {
  const DownloadVanillaPage({super.key, required this.version, required this.url, required this.name});

  final String version;
  final String url;
  final String name;

  @override
  _DownloadVanillaPageState createState() => _DownloadVanillaPageState();
}

class _DownloadVanillaPageState extends State<DownloadVanillaPage> {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  double _progress = 0.0;
  CancelToken? _cancelToken;
  bool _isDownloading = false;
  String? _error;
  bool _DownloadJson = false;
  bool _ParseGameJson = false;
  bool _ParseAssetJson = false;
  bool _DownloadAssetJson = false;
  bool _DownloadClient = false;
  bool _DownloadLibrary = false;
  bool _DownloadAsset = false;
  bool _ExtractedLwjglNativesPath = false;
  bool _ExtractedLwjglNatives = false;
  bool _WriteConfig = false;
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
  List<Map<String, String>> _failedLibraries = [];
  List<Map<String, String>> _failedAssets = [];
  bool _isRetrying = false;
  final int _maxRetries = 3;  // 最大重试次数
  int _currentRetryCount = 0;

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
      await flutterLocalNotificationsPlugin.initialize(initializationSettings);
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
        0, title, body, platformChannelSpecifics,
      );
    }
  }

  // 文件夹创建
  Future<void> _createGameDirectories() async {
    final prefs = await SharedPreferences.getInstance();
    final SelectedGamePath = prefs.getString('SelectedPath') ?? '';
    final GamePath = prefs.getString('Path_$SelectedGamePath') ?? '';
    final directory = Directory('$GamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
      debugPrint('创建目录: $GamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}');
      await LogUtil.info('创建目录: $GamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}');
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
        debugPrint('找到 ${librariesPath.length} 个库文件路径');
        debugPrint('找到 ${librariesURL.length} 个库文件URL');
        await LogUtil.info('找到 ${librariesPath.length} 个库文件路径,找到 ${librariesURL.length} 个库文件URL');
      }
      setState(() {
        _ParseGameJson = true;
      });
    } catch (e) {
        await _showNotification('解析JSON失败', e.toString());
        await LogUtil.error('解析JSON失败: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解析JSON失败: $e')),
        );
        setState(() {
          _error = '解析JSON失败: $e';
          _ParseGameJson = false;
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
      debugPrint('已解析 ${_assetHash.length} 个资产哈希值');
      await LogUtil.info('已解析 ${_assetHash.length} 个资产哈希值');
      setState(() {
        _ParseAssetJson = true;
      });
    } catch (e) {
      await _showNotification('解析资产索引失败', e.toString());
      await LogUtil.error('解析资产索引失败: $e');
      setState(() {
        _error = '解析资产索引失败: $e';
        _ParseAssetJson = false;
      });
    }
  }

  // 下载库
  Future<void> _DownloadLibraries({int concurrentDownloads = 20}) async {
    if (librariesURL.isEmpty || librariesPath.isEmpty) {
      debugPrint('库文件列表为空');
      await _showNotification('库文件列表为空', '无法下载库文件');
      await LogUtil.error('库文件列表为空，无法下载库文件');
      return;
    }
    if (!_isRetrying) {
      _failedLibraries.clear();
    }
    final prefs = await SharedPreferences.getInstance();
    final SelectedGamePath = prefs.getString('SelectedPath') ?? '';
    final GamePath = prefs.getString('Path_$SelectedGamePath') ?? '';
    List<Map<String, String>> downloadTasks = [];
    if (_isRetrying && _failedLibraries.isNotEmpty) {
      debugPrint('正在重试下载 ${_failedLibraries.length} 个失败的库文件');
      downloadTasks = _failedLibraries;
    } else {
      for (int i = 0; i < librariesURL.length; i++) {
        final url = librariesURL[i];
        final relativePath = librariesPath[i];
        final fullPath = '$GamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}$relativePath';
        final file = File(fullPath);
        if (!file.existsSync()) {
          downloadTasks.add({'url': url, 'path': fullPath});
        }
      }
    }
    final totalLibraries = downloadTasks.length;
    if (totalLibraries == 0) {
      debugPrint('所有库文件已存在，无需下载');
      await LogUtil.info('所有库文件已存在，无需下载');
      setState(() {
        _DownloadLibrary = true;
      });
      return;
    }
    int completedLibraries = 0;
    List<Map<String, String>> newFailedList = [];
    void updateProgress() {
      setState(() {
        _progress = completedLibraries / totalLibraries;
      });
    }
    debugPrint('开始下载 $totalLibraries 个库文件，并发数: $concurrentDownloads');
    await LogUtil.info('开始下载 $totalLibraries 个库文件，并发数: $concurrentDownloads');
    for (int i = 0; i < downloadTasks.length; i += concurrentDownloads) {
      int end = i + concurrentDownloads;
      if (end > downloadTasks.length) end = downloadTasks.length;
      List<Future<void>> batch = [];
      for (int j = i; j < end; j++) {
        final task = downloadTasks[j];
        batch.add(() async {
          try {
            await DownloadUtils.downloadFile(
              url: task['url']!,
              savePath: task['path']!,
              onProgress: (_) {},
              onSuccess: () {
                completedLibraries++;
                updateProgress();
              },
              onError: (error) async{
                completedLibraries++;
                newFailedList.add(task);
                debugPrint('下载库文件失败: $error, URL: ${task['url']}');
                await LogUtil.error('下载库文件失败: $error, URL: ${task['url']}');
              }
            );
          } catch (e) {
            completedLibraries++;
            newFailedList.add(task);
            debugPrint('下载库文件异常: $e, URL: ${task['url']}');
            await LogUtil.error('下载库文件异常: $e, URL: ${task['url']}');
          }
        }());
      }
      await Future.wait(batch);
      updateProgress();
      debugPrint('已完成: $completedLibraries/$totalLibraries, 失败: ${newFailedList.length}');
      await LogUtil.info('已完成: $completedLibraries/$totalLibraries, 失败: ${newFailedList.length}');
    }
    _failedLibraries = newFailedList;
    if (newFailedList.isNotEmpty && _currentRetryCount < _maxRetries) {
      _currentRetryCount++;
      debugPrint('准备重试下载 ${newFailedList.length} 个失败的库文件 (第 $_currentRetryCount 次重试)');
      await LogUtil.info('准备重试下载 ${newFailedList.length} 个失败的库文件 (第 $_currentRetryCount 次重试)');
      setState(() {
        _isRetrying = true;
      });
      await _DownloadLibraries(concurrentDownloads: concurrentDownloads);
    } else if (newFailedList.isNotEmpty) {
      debugPrint('已达最大并发重试次数，开始单线程重试 ${newFailedList.length} 个库文件');
      await LogUtil.warning('已达最大并发重试次数，开始单线程重试 ${newFailedList.length} 个库文件');
      await _singleThreadRetryDownload(newFailedList, "库文件", (progress) {
        setState(() {
          _progress = progress;
        });
      });
    }
    setState(() {
      _isRetrying = false;
      _currentRetryCount = 0;
      _DownloadLibrary = true;
      _progress = 0;
    });
  }

  // 下载资源
  Future<void> _DownloadAssets({int concurrentDownloads = 30}) async {
    final prefs = await SharedPreferences.getInstance();
    final SelectedGamePath = prefs.getString('SelectedPath') ?? '';
    final GamePath = prefs.getString('Path_$SelectedGamePath') ?? '';
    if (!_isRetrying) {
      _failedAssets.clear();
    }
    List<Map<String, String>> downloadTasks = [];
    if (_isRetrying && _failedAssets.isNotEmpty) {
      downloadTasks = _failedAssets;
    } else {
      for (int i = 0; i < _assetHash.length; i++) {
        final hash = _assetHash[i];
        final hashPrefix = hash.substring(0, 2);
        final AssetDir = '$GamePath${Platform.pathSeparator}assets${Platform.pathSeparator}objects${Platform.pathSeparator}$hashPrefix';
        final AssetPath = '$AssetDir${Platform.pathSeparator}$hash';
        final directory = Directory(AssetDir);
        if (!directory.existsSync()) {
          directory.createSync(recursive: true);
        }
        final file = File(AssetPath);
        if (!file.existsSync()) {
          final url = 'https://bmclapi2.bangbang93.com/assets/$hashPrefix/$hash';
          downloadTasks.add({'url': url, 'path': AssetPath});
        }
      }
    }
    final totalAssets = downloadTasks.length;
    if (totalAssets == 0) {
      debugPrint('所有资源文件已存在，无需下载');
      await LogUtil.info('所有资源文件已存在，无需下载');
      setState(() {
        _DownloadAsset = true;
      });
      return;
    }
    debugPrint('需要下载 $totalAssets 个资源文件，并发数: $concurrentDownloads');
    await LogUtil.info('需要下载 $totalAssets 个资源文件，并发数: $concurrentDownloads');
    int completedAssets = 0;
    List<Map<String, String>> newFailedList = [];
    void updateProgress() {
      setState(() {
        _progress = completedAssets / totalAssets;
      });
    }
    for (int i = 0; i < downloadTasks.length; i += concurrentDownloads) {
      int end = i + concurrentDownloads;
      if (end > downloadTasks.length) end = downloadTasks.length;
      List<Future<void>> batch = [];
      for (int j = i; j < end; j++) {
        final task = downloadTasks[j];
        batch.add(() async {
          try {
            await DownloadUtils.downloadFile(
              url: task['url']!,
              savePath: task['path']!,
              onProgress: (_) {},
              onSuccess: () {
                completedAssets++;
                if (completedAssets % 20 == 0 || completedAssets == totalAssets) {
                  updateProgress();
                }
              },
              onError: (error) async {
                completedAssets++;
                newFailedList.add(task);
                if (newFailedList.length % 10 == 0) {
                  debugPrint('已有 ${newFailedList.length} 个资源文件下载失败');
                  await LogUtil.error('已有 ${newFailedList.length} 个资源文件下载失败: $error, URL: ${task['url']}');
                }
              }
            );
          } catch (e) {
            completedAssets++;
            newFailedList.add(task);
          }
        }());
      }
      await Future.wait(batch);
      updateProgress();
      debugPrint('已完成: $completedAssets/$totalAssets, 失败: ${newFailedList.length}');
      await LogUtil.info('已完成: $completedAssets/$totalAssets, 失败: ${newFailedList.length}');
    }
    _failedAssets = newFailedList;
    if (newFailedList.isNotEmpty && _currentRetryCount < _maxRetries) {
      _currentRetryCount++;
      debugPrint('准备重试下载 ${newFailedList.length} 个失败的资源文件 (第 $_currentRetryCount 次重试)');
      await LogUtil.info('准备重试下载 ${newFailedList.length} 个失败的资源文件 (第 $_currentRetryCount 次重试)');
      setState(() {
        _isRetrying = true;
      });
      await _DownloadAssets(concurrentDownloads: concurrentDownloads);
    } else if (newFailedList.isNotEmpty) {
      debugPrint('已达最大并发重试次数，开始单线程重试 ${newFailedList.length} 个资源文件');
      await LogUtil.warning('已达最大并发重试次数，开始单线程重试 ${newFailedList.length} 个资源文件');
      await _singleThreadRetryDownload(newFailedList, "资源文件", (progress) {
        setState(() {
          _progress = progress;
        });
      });
    }
    setState(() {
      _isRetrying = false;
      _currentRetryCount = 0;
      _DownloadAsset = true;
    });
  }

  // 提取LWJGL本地库文件的名称和路径
  Future<void> ExtractLwjglNativeLibrariesPath(String jsonFilePath, String gamePath) async {
    final namesList = <String>[];
    final pathsList = <String>[];
    final file = File(jsonFilePath);
    if (!await file.exists()) {
      debugPrint('版本JSON文件不存在: $jsonFilePath');
      await LogUtil.error('版本JSON文件不存在: $jsonFilePath');
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
      debugPrint('JSON 解析失败: $e');
      await LogUtil.error('JSON 解析失败: $e');
      await _showNotification('提取LWJGL本地库失败', e.toString());
      setState(() {
        lwjglNativeNames = namesList;
        lwjglNativePaths = pathsList;
      });
      return;
    }
    final libs = root is Map ? root['libraries'] : null;
    if (libs is! List) {
      debugPrint('JSON中没有libraries字段或格式错误');
      await LogUtil.error('JSON中没有libraries字段或格式错误');
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
        debugPrint('找到LWJGL库: $fileName, 路径: $fullPath');
        await LogUtil.info('找到LWJGL库: $fileName, 路径: $fullPath');
      }
    }
    debugPrint('总共找到${namesList.length}个LWJGL本地库');
    await LogUtil.info('总共找到${namesList.length}个LWJGL本地库');
    setState(() {
      lwjglNativeNames = namesList;
      lwjglNativePaths = pathsList;
      _ExtractedLwjglNativesPath = true;
    });
  }

  // 提取LWJGL Natives
  Future<void> ExtractLwjglNatives() async {
    if (lwjglNativePaths.isEmpty || lwjglNativeNames.isEmpty) {
      debugPrint('没有找到LWJGL本地库，跳过提取');
      await LogUtil.warning('没有找到LWJGL本地库，跳过提取');
      setState(() {
        _ExtractedLwjglNativesPath = true;
      });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final SelectedGamePath = prefs.getString('SelectedPath') ?? '';
    final GamePath = prefs.getString('Path_$SelectedGamePath') ?? '';
    final nativesDir = '$GamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}${Platform.pathSeparator}natives';
    final nativesDirObj = Directory(nativesDir);
    if (!await nativesDirObj.exists()) {
      await nativesDirObj.create(recursive: true);
      debugPrint('创建natives目录: $nativesDir');
      await LogUtil.info('创建natives目录: $nativesDir');
    }
    debugPrint('开始提取LWJGL本地库到: $nativesDir');
    await LogUtil.info('开始提取LWJGL本地库到: $nativesDir');
    int successCount = 0;
    List<String> extractedFiles = [];
    for (int i = 0; i < lwjglNativePaths.length; i++) {
      final fullPath = lwjglNativePaths[i];
      final fileName = lwjglNativeNames[i];
      try {
        final jarDir = fullPath.substring(0, fullPath.lastIndexOf(Platform.pathSeparator));
        debugPrint('提取: $fileName 从 $jarDir 到 $nativesDir');
        await LogUtil.info('提取: $fileName 从 $jarDir 到 $nativesDir');
        // 调用ExtractNatives函数提取本地库
        final extracted = await ExtractNatives(jarDir, fileName, nativesDir);
        if (extracted.isNotEmpty) {
          successCount++;
          extractedFiles.addAll(extracted);
          debugPrint('成功从 $fileName 提取了 ${extracted.length} 个文件');
          await LogUtil.info('成功从 $fileName 提取了 ${extracted.length} 个文件');
        }
      } catch (e) {
        debugPrint('提取 $fileName 时出错: $e');
        await LogUtil.error('提取 $fileName 时出错: $e');
      }
    }
    debugPrint('完成LWJGL本地库提取, 共处理 ${lwjglNativePaths.length} 个文件, 成功: $successCount');
    await LogUtil.info('完成LWJGL本地库提取, 共处理 ${lwjglNativePaths.length} 个文件, 成功: $successCount');
    debugPrint('提取的文件: ${extractedFiles.join(', ')}');
    await LogUtil.info('提取的文件: ${extractedFiles.join(', ')}');
    setState(() {
      _ExtractedLwjglNatives = true;
    });
  }

  // 单线程
  Future<void> _singleThreadRetryDownload(List<Map<String, String>> failedList, String fileType,
      Function(double) updateProgressCallback) async {
    int total = failedList.length;
    int completed = 0;
    List<Map<String, String>> currentFailedList = List.from(failedList);
    while (currentFailedList.isNotEmpty) {
      List<Map<String, String>> nextRetryList = [];
      for (var task in currentFailedList) {
        bool success = false;
        int retryCount = 0;
        while (!success) {
          try {
            retryCount++;
            debugPrint('正在尝试下载$fileType: ${task['url']} (第 $retryCount 次尝试)');
            await LogUtil.info('正在尝试下载$fileType: ${task['url']} (第 $retryCount 次尝试)');
            bool downloadComplete = false;
            await DownloadUtils.downloadFile(
              url: task['url']!,
              savePath: task['path']!,
              onProgress: (_) {},
              onSuccess: () async{
                downloadComplete = true;
                debugPrint('$fileType下载成功: ${task['url']}');
                await LogUtil.info('$fileType下载成功: ${task['url']}');
              },
              onError: (error)async{
                debugPrint('$fileType下载失败: $error, URL: ${task['url']}');
                await LogUtil.error('$fileType下载失败: $error, URL: ${task['url']}');
              }
            );
            if (downloadComplete) {
              success = true;
              completed++;
              updateProgressCallback(completed / total);
              debugPrint('已完成: $completed/$total $fileType');
              await LogUtil.info('已完成: $completed/$total $fileType');
            } else {
              await Future.delayed(Duration(milliseconds: 500));
            }
          } catch (e) {
            debugPrint('$fileType下载异常: $e, URL: ${task['url']}');
            await LogUtil.error('$fileType下载异常: $e, URL: ${task['url']}');
            await Future.delayed(Duration(seconds: 1));
          }
        }
      }
      currentFailedList = nextRetryList;
    }
    debugPrint('所有$fileType已成功下载');
    await LogUtil.info('所有$fileType已成功下载');
  }

  // 文件下载
  Future<void> DownloadFile(path, url) async {
    setState(() {
      _isDownloading = true;
      _error = null;
    });
    bool success = false;
    _cancelToken = await DownloadUtils.downloadFile(
      url: url,
      savePath: path,
      onProgress: (progress) {
        setState(() {
          _progress = progress;
        });
      },
      onSuccess: () {
        setState(() {
          _isDownloading = false;
        });
        success = true;
      },
      onError: (error) {
        setState(() {
          _isDownloading = false;
          _error = error;
        });
        success = false;
      },
      onCancel: () {
        setState(() {
          _isDownloading = false;
        });
      },
    );
    if (!success) {
      throw Exception('下载失败: $url');
    }
  }

  // 获取系统内存
  void _getMemory(){
    int bytes = SysInfo.getTotalPhysicalMemory();
    // 内存错误修正
    if (bytes > (1024 * 1024 * 1024 * 1024) && bytes % 16384 == 0) {
      bytes = bytes ~/ 16384;
    }
    final physicalMemory = bytes ~/ (1024 * 1024 * 1024);
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
    debugPrint('已将 ${widget.name} 添加到游戏列表，当前列表: $gameList');
    await LogUtil.info('已将 ${widget.name} 添加到游戏列表，当前列表: $gameList');
    setState(() {
      _WriteConfig = true;
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
void _startDownload() async {
  final prefs = await SharedPreferences.getInstance();
  final SelectedGamePath = prefs.getString('SelectedPath') ?? '';
  final GamePath = prefs.getString('Path_$SelectedGamePath') ?? '';
  final VersionPath = '$GamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}';
  final GameJsonURL = replaceWithMirror(widget.url);
  try {
    await LogUtil.info('开始下载 ${widget.name} 版本');
    await _showNotification('开始下载', '正在下载 ${widget.name} 版本\n你可以将启动器置于后台,安装完成将有通知提醒');
    // 创建文件夹
    await _createGameDirectories();
    // 下载版本json
    try {
      await DownloadFile('$VersionPath${Platform.pathSeparator}${widget.name}.json', GameJsonURL);
      setState(() {
        _DownloadJson = true;
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
    await parseGameJson('$VersionPath${Platform.pathSeparator}${widget.name}.json');
    // 下载资源索引文件
    if (assetIndexURL != null) {
      final assetIndexDir = '$GamePath${Platform.pathSeparator}assets${Platform.pathSeparator}indexes';
      final assetIndexPath = '$assetIndexDir${Platform.pathSeparator}$assetIndexId.json';
      try {
        await DownloadFile('$GamePath${Platform.pathSeparator}assets${Platform.pathSeparator}indexes${Platform.pathSeparator}$assetIndexId.json', assetIndexURL!);
        setState(() {
          _DownloadAssetJson = true;
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
        await DownloadFile('$VersionPath${Platform.pathSeparator}${widget.name}.jar', clientURL);
        setState(() {
          _DownloadClient = true;
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
      await _DownloadLibraries(concurrentDownloads: 30);
      // 下载游戏资源
      await _DownloadAssets(concurrentDownloads: 30);
      // 提取LWJGL本地库路径
      await ExtractLwjglNativeLibrariesPath('$VersionPath${Platform.pathSeparator}${widget.name}.json',GamePath);
      // 提取LWJGL Natives
      await ExtractLwjglNatives();
      // 写入游戏配置文件
      await _writeGameConfig();
      // 完成通知
      await _showNotification('完成下载', '点击查看详细');
    }
  } catch (e) {
    setState(() {
      _error = e.toString();
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
              subtitle: Text(_DownloadJson ? '下载完成' : '下载中...'),
              trailing: _DownloadJson
                ? const Icon(Icons.check)
                : const CircularProgressIndicator(),
            ),
          ),
          if (_DownloadJson) ...[
            Card(
              child: ListTile(
                title: const Text('正在解析游戏Json'),
                subtitle: Text(_ParseGameJson ? '解析完成' : '解析中...'),
                trailing: _ParseGameJson
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            ),
            if (_ParseAssetJson) ...[
              Card(
                child: ListTile(
                  title: const Text('正在下载资源Json'),
                  subtitle: Text(_DownloadAssetJson ? '下载完成' : '下载中...'),
                  trailing: _DownloadAssetJson
                    ? const Icon(Icons.check)
                    : const CircularProgressIndicator(),
                ),
              ),
            ]
          ],
          if (_DownloadAssetJson) ...[
            Card(
              child: ListTile(
                title: const Text('正在解析资源Json'),
                subtitle: Text(_ParseAssetJson ? '解析完成' : '解析中...'),
                trailing: _ParseAssetJson
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            ),
          ],
          if (_ParseAssetJson) ...[
            Card(
              child: ListTile(
                title: const Text('正在下载客户端'),
                subtitle: Text(_DownloadClient ? '下载完成' : '下载中...'),
                trailing: _DownloadClient
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            ),
          ],
          if (_DownloadClient) ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('正在下载游戏库'),
                    subtitle: Text(_DownloadLibrary ? '下载完成' : '下载中... 已下载${(_progress * 100).toStringAsFixed(2)}%'),
                    trailing: _DownloadLibrary
                      ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
              if (!_DownloadLibrary)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: LinearProgressIndicator(value: _progress),
                ),
              ],
            ),
            )
          ],
          if (_DownloadLibrary) ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('正在下载游戏资源'),
                    subtitle: Text(_DownloadAsset ? '下载完成' : '下载中... 已下载${(_progress * 100).toStringAsFixed(2)}%'),
                    trailing: _DownloadAsset
                      ? const Icon(Icons.check)
                      : const CircularProgressIndicator(),
                  ),
                  if (!_DownloadAsset)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: LinearProgressIndicator(value: _progress),
                    ),
                ],
              ),
            )
          ],if (_DownloadAsset) ...[
            Card(
              child: ListTile(
                title: const Text('正在提取LWJGL路径'),
                subtitle: Text(_ExtractedLwjglNativesPath ? '提取完成' : '提取中...'),
                trailing: _ExtractedLwjglNativesPath
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            )
          ],if (_ExtractedLwjglNativesPath) ...[
            Card(
              child: ListTile(
                title: const Text('正在提取LWJGL'),
                subtitle: Text(_ExtractedLwjglNatives ? '提取完成' : '提取中...'),
                trailing: _ExtractedLwjglNatives
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            )],if (_ExtractedLwjglNatives) ...[
            Card(
              child: ListTile(
                title: const Text('正在写入配置文件'),
                subtitle: Text(_WriteConfig ? '写入完成' : '写入中...'),
                trailing: _WriteConfig
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            )
          ],
        ],
      ),
      floatingActionButton: _WriteConfig
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