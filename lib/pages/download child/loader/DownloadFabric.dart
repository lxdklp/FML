import 'package:flutter/material.dart';
import 'package:fml/function/download.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'dart:convert';
import 'package:system_info2/system_info2.dart';
import 'package:fml/function/ExtractNatives.dart';

class DownloadFabricPage extends StatefulWidget {
  const DownloadFabricPage({super.key, required this.version, required this.url, required this.name, required this.fabricVersion, required this.fabricLoader});

  final String version;
  final String url;
  final String name;
  final String fabricVersion;
  final Map<String, dynamic>? fabricLoader;

  @override
  _DownloadFabricPageState createState() => _DownloadFabricPageState();
}

class _DownloadFabricPageState extends State<DownloadFabricPage> {
  double _progress = 0.0;
  CancelToken? _cancelToken;
  bool _isDownloading = false;
  String? _error;
  bool _SaveFabricJson = false;
  bool _DownloadJson = false;
  bool _ParseGameJson = false;
  bool _ParseAssetJson = false;
  bool _ParseFabricJson = false;
  bool _DownloadAssetJson = false;
  bool _DownloadClient = false;
  bool _DownloadLibrary = false;
  bool _DownloadAsset = false;
  bool _ExtractedLwjglNativesPath = false;
  bool _ExtractedLwjglNatives = false;
  bool _DownloadFabric = false;
  bool _WriteConfig = false;
  int _mem = 1;
  String _name = '';

  String? assetIndexURL;
  String? clientURL;
  String? assetIndexId;
  List<String> librariesPath = [];
  List<String> librariesURL = [];
  List<String> lwjglNativeNames = [];
  List<String> lwjglNativePaths = [];
  final List<String> _assetHash = [];
  List<Map<String, String>> _failedLibraries = [];
  List<Map<String, String>> _failedAssets = [];
  final List<Map<String, String>> _fabricDownloadTasks = [];
  List<Map<String, String>> _failedFabricFiles = [];
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

  // 文件夹创建
  Future<void> _createGameDirectories() async {
    final prefs = await SharedPreferences.getInstance();
    final SelectedGamePath = prefs.getString('SelectedPath') ?? '';
    final GamePath = prefs.getString('Path_$SelectedGamePath') ?? '';
    final directory = Directory('$GamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
      debugPrint('创建目录: $GamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}');
    }
  }

  // 添加保存Fabric JSON到本地
  Future<void> saveLoaderToJson(String jsonPath) async {
    try {
      if (widget.fabricLoader == null) {
        debugPrint('fabricLoader为空，无法保存');
        return;
      }
      final String jsonString = jsonEncode(widget.fabricLoader);
      final String dirPath = jsonPath;
      final String filePath = '$dirPath/fabric.json';
      final Directory directory = Directory(dirPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
        debugPrint('已创建目录: $dirPath');
      }
      // 创建文件并写入JSON内容
      final File file = File(filePath);
      await file.writeAsString(jsonString);
      debugPrint('已成功将fabricLoader保存到: $filePath');
      debugPrint('fabricLoader内容: $jsonString');
      setState(() {
        _SaveFabricJson = true;
      });
    } catch (e) {
      debugPrint('保存JSON时出错: $e');
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
      }
      setState(() {
        _ParseGameJson = true;
      });
    } catch (e) {
      debugPrint('解析JSON失败: $e');
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
      setState(() {
        _ParseAssetJson = true;
      });
    } catch (e) {
      debugPrint('解析资产索引失败: $e');
      setState(() {
        _error = '解析资产索引失败: $e';
        _ParseAssetJson = false;
      });
    }
  }

  // 解析 Fabric JSON
  Future<void> parseFabricLoaderJson() async {
  try {
    if (widget.fabricLoader == null) {
      debugPrint('fabricLoader为空，无法解析');
      return;
    }
    _fabricDownloadTasks.clear();
    final Map<String, dynamic> loaderJson = widget.fabricLoader!;
    // 1. 解析 Loader
    if (loaderJson.containsKey('loader') && loaderJson['loader'] != null) {
      final loaderInfo = loaderJson['loader'];
      if (loaderInfo.containsKey('maven') && loaderInfo['maven'] != null) {
        final String loaderMaven = loaderInfo['maven'];
        final List<String> loaderParts = loaderMaven.split(':');
        if (loaderParts.length >= 3) {
          final String group = loaderParts[0].replaceAll('.', '/');
          final String artifact = loaderParts[1];
          final String version = loaderParts[2];
          final String relativePath = '$group/$artifact/$version/$artifact-$version.jar';
          final String url = 'https://bmclapi2.bangbang93.com/maven/$group/$artifact/$version/$artifact-$version.jar';
          _fabricDownloadTasks.add({'url': replaceWithMirror(url), 'path': relativePath});
          debugPrint('添加Fabric Loader: $relativePath');
        }
      }
    }
    // 2. 解析 Intermediary
    if (loaderJson.containsKey('intermediary') && loaderJson['intermediary'] != null) {
      final intermediaryInfo = loaderJson['intermediary'];
      if (intermediaryInfo.containsKey('maven') && intermediaryInfo['maven'] != null) {
        final String intermediaryMaven = intermediaryInfo['maven'];
        final List<String> parts = intermediaryMaven.split(':');
        if (parts.length >= 3) {
          final String group = parts[0].replaceAll('.', '/');
          final String artifact = parts[1];
          final String version = parts[2];
          final String relativePath = '$group/$artifact/$version/$artifact-$version.jar';
          final String url = 'https://bmclapi2.bangbang93.com/maven/$group/$artifact/$version/$artifact-$version.jar';
          _fabricDownloadTasks.add({'url': replaceWithMirror(url), 'path': relativePath});
          debugPrint('添加Intermediary: $relativePath');
        }
      }
    }
    // 3. 解析库文件
    if (loaderJson.containsKey('launcherMeta') &&
        loaderJson['launcherMeta'] != null &&
        loaderJson['launcherMeta'].containsKey('libraries')) {
      final libraries = loaderJson['launcherMeta']['libraries'];
      // 3.1 解析通用库
      if (libraries.containsKey('common') && libraries['common'] is List) {
        final List<dynamic> commonLibs = libraries['common'];
        for (var lib in commonLibs) {
          if (lib.containsKey('name')) {
            final String name = lib['name'];
            String baseUrl = lib.containsKey('url') ? lib['url'] : 'https://bmclapi2.bangbang93.com/maven/';
            final List<String> parts = name.split(':');
            if (parts.length >= 3) {
              final String group = parts[0].replaceAll('.', '/');
              final String artifact = parts[1];
              String version = parts[2];
              // 处理可能包含额外信息的版本号
              if (version.contains('@')) {
                version = version.split('@')[0];
              }
              final String relativePath = '$group/$artifact/$version/$artifact-$version.jar';
              final String fullUrl = '$baseUrl$group/$artifact/$version/$artifact-$version.jar';
              _fabricDownloadTasks.add({'url': replaceWithMirror(fullUrl), 'path': relativePath});
            }
          }
        }
      }
      setState(() {
        _ParseFabricJson = true;
      });
    }
    debugPrint('找到 ${_fabricDownloadTasks.length} 个Fabric文件需要下载');
    setState(() {
      _ParseFabricJson = true;
    });
  } catch (e) {
    debugPrint('解析Fabric Loader JSON失败: $e');
    setState(() {
      _error = '解析Fabric Loader JSON失败: $e';
      _ParseFabricJson = false;
    });
  }
}

  // 下载库
  Future<void> _DownloadLibraries({int concurrentDownloads = 20}) async {
    if (librariesURL.isEmpty || librariesPath.isEmpty) {
      debugPrint('库文件列表为空');
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
              onError: (error) {
                completedLibraries++;
                newFailedList.add(task);
                debugPrint('下载库文件失败: $error, URL: ${task['url']}');
              }
            );
          } catch (e) {
            completedLibraries++;
            newFailedList.add(task);
            debugPrint('下载库文件异常: $e, URL: ${task['url']}');
          }
        }());
      }
      await Future.wait(batch);
      updateProgress();
      debugPrint('已完成: $completedLibraries/$totalLibraries, 失败: ${newFailedList.length}');
    }
    _failedLibraries = newFailedList;
    if (newFailedList.isNotEmpty && _currentRetryCount < _maxRetries) {
      _currentRetryCount++;
      debugPrint('准备重试下载 ${newFailedList.length} 个失败的库文件 (第 $_currentRetryCount 次重试)');
      setState(() {
        _isRetrying = true;
      });
      await _DownloadLibraries(concurrentDownloads: concurrentDownloads);
    } else if (newFailedList.isNotEmpty) {
      debugPrint('已达最大并发重试次数，开始单线程无限重试 ${newFailedList.length} 个库文件');
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
      setState(() {
        _DownloadAsset = true;
      });
      return;
    }
    debugPrint('需要下载 $totalAssets 个资源文件，并发数: $concurrentDownloads');
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
              onError: (error) {
                completedAssets++;
                newFailedList.add(task);
                if (newFailedList.length % 10 == 0) {
                  debugPrint('已有 ${newFailedList.length} 个资源文件下载失败');
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
    }
    _failedAssets = newFailedList;
    if (newFailedList.isNotEmpty && _currentRetryCount < _maxRetries) {
      _currentRetryCount++;
      debugPrint('准备重试下载 ${newFailedList.length} 个失败的资源文件 (第 $_currentRetryCount 次重试)');
      setState(() {
        _isRetrying = true;
      });
      await _DownloadAssets(concurrentDownloads: concurrentDownloads);
    } else if (newFailedList.isNotEmpty) {
      debugPrint('已达最大并发重试次数，开始单线程无限重试 ${newFailedList.length} 个资源文件');
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
      setState(() {
        lwjglNativeNames = namesList;
        lwjglNativePaths = pathsList;
        _ExtractedLwjglNativesPath = true;
      });
      return;
    }
    late final dynamic root;
    try {
      root = jsonDecode(await file.readAsString());
    } catch (e) {
      debugPrint('JSON 解析失败: $e');
      setState(() {
        lwjglNativeNames = namesList;
        lwjglNativePaths = pathsList;
        _ExtractedLwjglNativesPath = true;
      });
      return;
    }
    final libs = root is Map ? root['libraries'] : null;
    if (libs is! List) {
      debugPrint('JSON中没有libraries字段或格式错误');
      setState(() {
        lwjglNativeNames = namesList;
        lwjglNativePaths = pathsList;
        _ExtractedLwjglNativesPath = true;
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
      }
    }
    debugPrint('总共找到${namesList.length}个LWJGL本地库');
    setState(() {
      lwjglNativeNames = namesList;
      lwjglNativePaths = pathsList;
    });
  }

  // 提取LWJGL Natives
  Future<void> ExtractLwjglNatives() async {
    if (lwjglNativePaths.isEmpty || lwjglNativeNames.isEmpty) {
      debugPrint('没有找到LWJGL本地库，跳过提取');
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
    }
    debugPrint('开始提取LWJGL本地库到: $nativesDir');
    int successCount = 0;
    List<String> extractedFiles = [];
    for (int i = 0; i < lwjglNativePaths.length; i++) {
      final fullPath = lwjglNativePaths[i];
      final fileName = lwjglNativeNames[i];
      try {
        final jarDir = fullPath.substring(0, fullPath.lastIndexOf(Platform.pathSeparator));
        debugPrint('提取: $fileName 从 $jarDir 到 $nativesDir');
        // 调用ExtractNatives函数提取本地库
        final extracted = await ExtractNatives(jarDir, fileName, nativesDir);
        if (extracted.isNotEmpty) {
          successCount++;
          extractedFiles.addAll(extracted);
          debugPrint('成功从 $fileName 提取了 ${extracted.length} 个文件');
        }
      } catch (e) {
        debugPrint('提取 $fileName 时出错: $e');
      }
    }
    debugPrint('完成LWJGL本地库提取, 共处理 ${lwjglNativePaths.length} 个文件, 成功: $successCount');
    debugPrint('提取的文件: ${extractedFiles.join(', ')}');
  }

  // 下载Fabric
  Future<void> _DownloadFabricLibraries({int concurrentDownloads = 20}) async {
    if (_fabricDownloadTasks.isEmpty) {
      debugPrint('Fabric库文件列表为空');
      setState(() {
        _DownloadFabric = true;
      });
      return;
    }
    if (!_isRetrying) {
      _failedFabricFiles.clear();
    }
    final prefs = await SharedPreferences.getInstance();
    final SelectedGamePath = prefs.getString('SelectedPath') ?? '';
    final GamePath = prefs.getString('Path_$SelectedGamePath') ?? '';
    List<Map<String, String>> downloadTasks = [];
    if (_isRetrying && _failedFabricFiles.isNotEmpty) {
      downloadTasks = _failedFabricFiles;
    } else {
      for (var task in _fabricDownloadTasks) {
        final relativePath = task['path']!;
        final url = task['url']!;
        final fullPath = '$GamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}$relativePath';
        final directory = Directory(fullPath.substring(0, fullPath.lastIndexOf(Platform.pathSeparator)));
        if (!directory.existsSync()) {
          directory.createSync(recursive: true);
        }
        final file = File(fullPath);
        if (!file.existsSync()) {
          downloadTasks.add({'url': url, 'path': fullPath});
        }
      }
    }
    final totalTasks = downloadTasks.length;
    if (totalTasks == 0) {
      debugPrint('所有Fabric库文件已存在，无需下载');
      setState(() {
        _DownloadFabric = true;
      });
      return;
    }
    debugPrint('需要下载 $totalTasks 个Fabric文件，并发数: $concurrentDownloads');
    int completedTasks = 0;
    List<Map<String, String>> newFailedList = [];
    void updateProgress() {
      setState(() {
        _progress = completedTasks / totalTasks;
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
                completedTasks++;
                updateProgress();
              },
              onError: (error) {
                completedTasks++;
                newFailedList.add(task);
                debugPrint('下载Fabric文件失败: $error, URL: ${task['url']}');
              }
            );
          } catch (e) {
            completedTasks++;
            newFailedList.add(task);
            debugPrint('下载Fabric文件异常: $e, URL: ${task['url']}');
          }
        }());
      }
      await Future.wait(batch);
      updateProgress();
      debugPrint('已完成: $completedTasks/$totalTasks, 失败: ${newFailedList.length}');
    }
    _failedFabricFiles = newFailedList;
    if (newFailedList.isNotEmpty && _currentRetryCount < _maxRetries) {
      _currentRetryCount++;
      debugPrint('准备重试下载 ${newFailedList.length} 个失败的Fabric文件 (第 $_currentRetryCount 次重试)');
      setState(() {
        _isRetrying = true;
      });
      await _DownloadFabricLibraries(concurrentDownloads: concurrentDownloads);
    } else if (newFailedList.isNotEmpty) {
      debugPrint('已达最大并发重试次数，开始单线程无限重试 ${newFailedList.length} 个Fabric文件');
      await _singleThreadRetryDownload(newFailedList, "Fabric文件", (progress) {
        setState(() {
          _progress = progress;
        });
      });
    }
    setState(() {
      _isRetrying = false;
      _currentRetryCount = 0;
      _DownloadFabric = true;
    });
  }

  // 单线程重新尝试
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
            bool downloadComplete = false;
            await DownloadUtils.downloadFile(
              url: task['url']!,
              savePath: task['path']!,
              onProgress: (_) {},
              onSuccess: () {
                downloadComplete = true;
                debugPrint('$fileType下载成功: ${task['url']}');
              },
              onError: (error) {
                debugPrint('$fileType下载失败: $error, URL: ${task['url']}');
              }
            );
            if (downloadComplete) {
              success = true;
              completed++;
              updateProgressCallback(completed / total);
              debugPrint('已完成: $completed/$total $fileType');
            } else {
              // 短暂延迟后再重试
              await Future.delayed(Duration(milliseconds: 500));
            }
          } catch (e) {
            debugPrint('$fileType下载异常: $e, URL: ${task['url']}');
            await Future.delayed(Duration(seconds: 1));
          }
        }
      }
      currentFailedList = nextRetryList;
    }
    debugPrint('所有$fileType已成功下载');
  }

  // 文件下载
  Future<void> DownloadFile(path,url) async {
    setState(() {
      _isDownloading = true;
      _error = null;
    });
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
        }
        );
      },
      onError: (error) {
        setState(() {
          _isDownloading = false;
          _error = error;
        });
      },
      onCancel: () {
        setState(() {
          _isDownloading = false;
        });
      },
    );
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
      'Fabric',
      ''
    ];
    final key = 'Config_${_name}_${widget.name}';
    await prefs.setStringList(key, defaultConfig);
    gameList.add(widget.name);
    await prefs.setStringList('Game_$_name', gameList);
    debugPrint('已将 ${widget.name} 添加到游戏列表，当前列表: $gameList');
  }

  @override
  void initState() {
    super.initState();
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
    // 创建文件夹
    await _createGameDirectories();
    // 下载版本json
    await DownloadFile('$VersionPath${Platform.pathSeparator}${widget.name}.json', GameJsonURL);
    setState(() {
      _DownloadJson = true;
    });
    // 保存Fabric JSON到本地
    await saveLoaderToJson(VersionPath);
    // 解析游戏Json
    await parseGameJson('$VersionPath${Platform.pathSeparator}${widget.name}.json');
    // 下载资产索引文件
    if (assetIndexURL != null) {
      final assetIndexDir = '$GamePath${Platform.pathSeparator}assets${Platform.pathSeparator}indexes';
      final assetIndexPath = '$assetIndexDir${Platform.pathSeparator}$assetIndexId.json';
      // 下载资产索引
      await DownloadFile('$GamePath${Platform.pathSeparator}assets${Platform.pathSeparator}indexes${Platform.pathSeparator}$assetIndexId.json', assetIndexURL!);
      setState(() {
        _DownloadAssetJson = true;
      });
      // 解析资产索引
      await parseAssetIndex(assetIndexPath);
      await parseFabricLoaderJson();
      // 下载客户端
      await DownloadFile('$VersionPath${Platform.pathSeparator}${widget.name}.jar', clientURL);
      setState(() {
        _DownloadClient = true;
      });
      // 下载库文件
      await _DownloadLibraries(concurrentDownloads: 30);
      setState(() {
        _DownloadLibrary = true;
        _progress = 0;
      });
      // 下载资源文件
      await _DownloadAssets(concurrentDownloads: 30);
      setState(() {
        _DownloadAsset = true;
      });
      // 提取LWJGL本地库路径
      await ExtractLwjglNativeLibrariesPath('$VersionPath${Platform.pathSeparator}${widget.name}.json',GamePath);
      setState(() {
        _ExtractedLwjglNativesPath = true;
      });
      // 提取LWJGL Natives
      await ExtractLwjglNatives();
      setState(() {
        _ExtractedLwjglNatives = true;
      });
      // 下载 Fabric
      await _DownloadFabricLibraries(concurrentDownloads: 30);
      setState(() {
        _DownloadFabric = true;
      });
      // 写入游戏配置
      await _writeGameConfig();
      setState(() {
        _WriteConfig = true;
      });
    }
  } catch (e) {
    setState(() {
      _error = e.toString();
    });
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('正在下载 ${widget.version} + Fabric ${widget.fabricVersion}'),
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
                title: const Text('正在保存Fabric Json'),
                subtitle: Text(_SaveFabricJson ? '保存完成' : '保存中...'),
                trailing: _SaveFabricJson
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            ),
            if (_SaveFabricJson) ...[
              Card(
                child: ListTile(
                  title: const Text('正在解析游戏Json'),
                  subtitle: Text(_ParseGameJson ? '解析完成' : '解析中...'),
                  trailing: _ParseGameJson
                    ? const Icon(Icons.check)
                    : const CircularProgressIndicator(),
                ),
              ),
            ],
            if (_ParseGameJson) ...[
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
                title: const Text('正在解析Fabric Json'),
                subtitle: Text(_ParseFabricJson ? '解析完成' : '解析中...'),
                trailing: _ParseFabricJson
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            ),
          ],
          if (_ParseFabricJson) ...[
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
          ],
          if (_DownloadAsset) ...[
            Card(
              child: ListTile(
                title: const Text('正在提取LWJGL路径'),
                subtitle: Text(_ExtractedLwjglNativesPath ? '提取完成' : '提取中...'),
                trailing: _ExtractedLwjglNativesPath
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            )],
            if (_ExtractedLwjglNativesPath) ...[
            Card(
              child: ListTile(
                title: const Text('正在提取LWJGL'),
                subtitle: Text(_ExtractedLwjglNatives ? '提取完成' : '提取中...'),
                trailing: _ExtractedLwjglNatives
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            )
          ],
          if (_ExtractedLwjglNatives) ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('正在下载Fabric'),
                    subtitle: Text(_DownloadFabric ? '下载完成' : '下载中... 已下载${(_progress * 100).toStringAsFixed(2)}%'),
                    trailing: _DownloadFabric
                      ? const Icon(Icons.check)
                      : const CircularProgressIndicator(),
                  ),
                  if (!_DownloadFabric)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: LinearProgressIndicator(value: _progress),
                    ),
                ],
              ),
            )
          ],
          if (_DownloadFabric) ...[
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