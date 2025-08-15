import 'package:flutter/material.dart';
import 'package:fml/function/download.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'dart:convert';
import 'package:system_info2/system_info2.dart';
import 'package:archive/archive.dart';

class DownloadNeoForgePage extends StatefulWidget {
  const DownloadNeoForgePage({super.key, required this.version, required this.url, required this.name, required this.neoforgeVersion});

  final String version;
  final String url;
  final String name;
  final String neoforgeVersion;

  @override
  _DownloadNeoForgePageState createState() => _DownloadNeoForgePageState();
}

class _DownloadNeoForgePageState extends State<DownloadNeoForgePage> {
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
  bool _DownloadNeoForge = false;
  bool _ExtractNeoForgeInstaller = false;
  bool _ParseNeoForgeInstallerJson = false;
  bool _DownloadNeoForgeLibrary = false;
  bool _NeoForgeInstalled = false;
  bool _WriteConfig = false;

  int _mem = 1;
  String _name = '';

  String? assetIndexURL;
  String? clientURL;
  String? assetIndexId;
  List<String> librariesPath = [];
  List<String> librariesURL = [];
  List<String> neoForgeLibrariesPath = [];
  List<String> neoForgeLibrariesURL = [];
  final List<String> _assetHash = [];
  List<Map<String, String>> _failedLibraries = [];
  List<Map<String, String>> _failedAssets = [];
  bool _isRetrying = false;
  final int _maxRetries = 3;  // 最大重试次数
  int _currentRetryCount = 0;
  String _installerJson = '';

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

  // 提取NeoForge
  Future<void> _extractNeoForgeInstaller() async {
    try {
      // 读取JAR文件
      final prefs = await SharedPreferences.getInstance();
      final SelectedGamePath = prefs.getString('SelectedPath') ?? '';
      final GamePath = prefs.getString('Path_$SelectedGamePath') ?? '';
      final NeoForgePath = '$GamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}${Platform.pathSeparator}neoforge-installer.jar';
      final bytes = await File(NeoForgePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      // 提取install_profile.json文件
      for (final file in archive) {
        if (file.name == 'install_profile.json') {
          final content = file.content as List<int>;
          _installerJson = utf8.decode(content);
          // 保存到文件
          final jsonFile = File('$GamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}${Platform.pathSeparator}install_profile.json');
          await jsonFile.writeAsBytes(content);
          break;
        }
      }
      if (_installerJson.isEmpty) {
        throw Exception('无法从安装器中提取install_profile.json');
      }
    } catch (e) {
      throw Exception('提取NeoForge安装器失败: $e');
    }
  }

  // 解析NeoForge安装器JSON
  void _parseNeoForgeInstallerJson() {
    neoForgeLibrariesURL.clear();
    neoForgeLibrariesPath.clear();
    if (_installerJson.isEmpty) return;
    try {
      final json = jsonDecode(_installerJson);
      if (json['libraries'] != null && json['libraries'] is List) {
        debugPrint('找到NeoForge libraries，开始解析...');
        for (var lib in json['libraries']) {
          if (lib['downloads'] != null && lib['downloads']['artifact'] != null) {
            final artifact = lib['downloads']['artifact'];
            if (artifact['path'] != null) {
              neoForgeLibrariesPath.add(artifact['path']);
            }
            if (artifact['url'] != null) {
              String url = artifact['url'];
              url = url.replaceAll(
                'https://maven.neoforged.net/releases/net',
                'https://bmclapi2.bangbang93.com/maven/net'
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
              debugPrint('解析Maven坐标失败: $mavenCoords, 错误: $e');
            }
          }
        }
        librariesPath.addAll(neoForgeLibrariesPath);
        librariesURL.addAll(neoForgeLibrariesURL);
        debugPrint('成功解析NeoForge libraries: ${neoForgeLibrariesURL.length}个');
        debugPrint('第一个库URL示例: ${neoForgeLibrariesURL.isNotEmpty ? neoForgeLibrariesURL[0] : "无"}');
        debugPrint('第一个库路径示例: ${neoForgeLibrariesPath.isNotEmpty ? neoForgeLibrariesPath[0] : "无"}');
      } else {
        debugPrint('未找到NeoForge libraries或格式不正确');
      }
    } catch (e) {
      debugPrint('解析NeoForge安装器JSON失败: $e');
    }
  }

  // 下载NeoForge库
  Future<void> _DownloadNeoForgeLibraries({int concurrentDownloads = 20}) async {
    if (neoForgeLibrariesURL.isEmpty || neoForgeLibrariesPath.isEmpty) {
      debugPrint('开始处理NeoForge库文件下载，列表长度：${neoForgeLibrariesURL.length}');
      debugPrint('NeoForge库文件列表为空');
      setState(() {
        _DownloadNeoForge = true;
      });
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
      debugPrint('正在重试下载 ${_failedLibraries.length} 个失败的NeoForge库文件');
      downloadTasks = _failedLibraries;
    } else {
      final libraryDir = Directory('$GamePath${Platform.pathSeparator}libraries');
      if (!await libraryDir.exists()) {
        await libraryDir.create(recursive: true);
      }
      for (int i = 0; i < neoForgeLibrariesURL.length; i++) {
        final url = neoForgeLibrariesURL[i];
        final relativePath = neoForgeLibrariesPath[i];
        final fullPath = '$GamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}$relativePath';
        final file = File(fullPath);
        if (!file.existsSync()) {
          downloadTasks.add({'url': url, 'path': fullPath});
        }
      }
    }
    final totalLibraries = downloadTasks.length;
    if (totalLibraries == 0) {
      debugPrint('所有NeoForge库文件已存在，无需下载');
      setState(() {
        _DownloadNeoForge = true;
      });
      return;
    }
    debugPrint('开始下载 $totalLibraries 个NeoForge库文件，并发数: $concurrentDownloads');
    int completedLibraries = 0;
    List<Map<String, String>> newFailedList = [];
    void updateProgress() {
      setState(() {
        _progress = completedLibraries / totalLibraries;
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
                completedLibraries++;
                updateProgress();
              },
              onError: (error) {
                completedLibraries++;
                newFailedList.add(task);
                debugPrint('下载NeoForge库文件失败: $error, URL: ${task['url']}');
              }
            );
          } catch (e) {
            completedLibraries++;
            newFailedList.add(task);
            debugPrint('下载NeoForge库文件异常: $e, URL: ${task['url']}');
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
      debugPrint('准备重试下载 ${newFailedList.length} 个失败的NeoForge库文件 (第 $_currentRetryCount 次重试)');
      setState(() {
        _isRetrying = true;
      });
      await _DownloadNeoForgeLibraries(concurrentDownloads: concurrentDownloads); // 修正：调用自身重试而不是_DownloadLibraries
    } else if (newFailedList.isNotEmpty) {
      debugPrint('已达最大并发重试次数，开始单线程无限重试 ${newFailedList.length} 个NeoForge库文件');
      await _singleThreadRetryDownload(newFailedList, "NeoForge库文件", (progress) {
        setState(() {
          _progress = progress;
        });
      });
    }
    setState(() {
      _isRetrying = false;
      _currentRetryCount = 0;
      _DownloadNeoForge = true;
    });
  }

  // 执行NeoForge安装器
  Future<void> _executeNeoForgeInstaller() async {
    final prefs = await SharedPreferences.getInstance();
    final SelectedGamePath = prefs.getString('SelectedPath') ?? '';
    final GamePath = prefs.getString('Path_$SelectedGamePath') ?? '';
    final installerPath = '$GamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}${Platform.pathSeparator}neoforge-installer.jar';
    final proc = await Process.start('java', [
      '-jar', installerPath,
      '--installClient', GamePath
    ]);
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => debugPrint('[OUT] $l'));
    proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => debugPrint('[ERR] $l'));
    final code = await proc.exitCode;
    debugPrint('退出码: $code');
      if (code != 0) {
        throw Exception('NeoForge安装器执行失败，退出码: $code');
      }
      debugPrint('NeoForge安装器执行成功');
  }

  // 单线程重试下载
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
      'NeoForge',
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
  debugPrint('开始下载: ${widget.name} NeoForge');
  final prefs = await SharedPreferences.getInstance();
  final SelectedGamePath = prefs.getString('SelectedPath') ?? '';
  final GamePath = prefs.getString('Path_$SelectedGamePath') ?? '';
  final VersionPath = '$GamePath${Platform.pathSeparator}versions${Platform.pathSeparator}${widget.name}';
  final GameJsonURL = replaceWithMirror(widget.url);
  final NeoForgeURL = 'https://bmclapi2.bangbang93.com/maven/net/neoforged/neoforge/${widget.neoforgeVersion}/neoforge-${widget.neoforgeVersion}-installer.jar';
  try {
    // 创建文件夹
    await _createGameDirectories();
    // 下载版本json
    await DownloadFile('$VersionPath${Platform.pathSeparator}${widget.name}.json', GameJsonURL);
    setState(() {
      _DownloadJson = true;
    });
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
      await _DownloadAssets(concurrentDownloads: 30);
      setState(() {
        _DownloadAsset = true;
      });
      // 下载NeoForge安装器
      debugPrint('开始下载: $VersionPath,$NeoForgeURL');
      await DownloadFile('$VersionPath${Platform.pathSeparator}neoforge-installer.jar',NeoForgeURL);
      setState(() {
        _DownloadNeoForge = true;
      });
      // 提取NeoForge安装器
      await _extractNeoForgeInstaller();
      setState(() {
        _ExtractNeoForgeInstaller = true;
      });
      // 解析NeoForge安装器JSON
      _parseNeoForgeInstallerJson();
      setState(() {
        _ParseNeoForgeInstallerJson = true;
      });
      // 下载NeoForge库文件
      await _DownloadNeoForgeLibraries();
      setState(() {
        _DownloadNeoForgeLibrary = true;
      });
      await _executeNeoForgeInstaller();
      setState(() {
        _NeoForgeInstalled = true;
      });
      // 写入游戏配置文件
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
        title: Text('正在下载${widget.version} + NeoForge ${widget.neoforgeVersion}'),
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
          ],
          if (_DownloadAsset) ...[
            Card(
              child: ListTile(
                title: const Text('正在下载NeoForge'),
                subtitle: Text(_DownloadNeoForge ? '下载完成' : '下载中...'),
                trailing: _DownloadNeoForge
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            )
          ],if (_DownloadNeoForge) ...[
            Card(
              child: ListTile(
                title: const Text('正在解压NeoForge安装列表'),
                subtitle: Text(_ExtractNeoForgeInstaller ? '解压完成' : '解压中...'),
                trailing: _ExtractNeoForgeInstaller
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            )
          ],if (_ExtractNeoForgeInstaller) ...[
            Card(
              child: ListTile(
                title: const Text('正在解析NeoForge Json'),
                subtitle: Text(_ParseNeoForgeInstallerJson ? '解析完成' : '解析中...'),
                trailing: _ParseNeoForgeInstallerJson
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            )
          ],if (_ParseNeoForgeInstallerJson) ...[
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('正在下载NeoForge库文件'),
                    subtitle: Text(_DownloadNeoForgeLibrary ? '下载完成' : '下载中... 已下载${(_progress * 100).toStringAsFixed(2)}%'),
                    trailing: _DownloadNeoForgeLibrary
                      ? const Icon(Icons.check)
                      : const CircularProgressIndicator(),
                  ),
                  if (!_DownloadNeoForgeLibrary)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: LinearProgressIndicator(value: _progress),
                    ),
                ],
              ),
            )
          ],if (_DownloadNeoForgeLibrary) ...[
            Card(
              child: ListTile(
                title: const Text('正在安装NeoForge'),
                subtitle: Text(_NeoForgeInstalled ? '安装完成' : '安装中...'),
                trailing: _NeoForgeInstalled
                  ? const Icon(Icons.check)
                  : const CircularProgressIndicator(),
              ),
            )
          ],if (_NeoForgeInstalled) ...[
            Card(
              child: ListTile(
                title: const Text('正在写入配置文件'),
                subtitle: Text(_NeoForgeInstalled ? '写入完成' : '写入中...'),
                trailing: _NeoForgeInstalled
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