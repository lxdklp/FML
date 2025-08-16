import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

// library获取
Future<Set<String>> loadLibraryArtifactPaths(String versionJsonPath, String gamePath) async {
  final file = File(versionJsonPath);
  if (!await file.exists()) return {};
  late final dynamic root;
  try {
    root = jsonDecode(await file.readAsString());
  } catch (e) {
    debugPrint('JSON 解析失败: $e');
    return {};
  }
  final libs = root is Map ? root['libraries'] : null;
  if (libs is! List) return {};
  final Set<String> result = {};
  for (final item in libs) {
    if (item is! Map) continue;
    final downloads = item['downloads'];
    if (downloads is! Map) continue;
    final artifact = downloads['artifact'];
    if (artifact is! Map) continue;
    final path = artifact['path'];
    if (path is String && path.isNotEmpty) {
      final fullPath = normalizePath('$gamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}$path');
      result.add(fullPath);
    }
  }
  return result;
}

String normalizePath(String path) {
  return p.normalize(path);
}

// 直接从库名称构建路径 (用于install_profile中没有downloads.artifact.path的情况)
Set<String> buildLibraryPaths(List<Map<String, dynamic>> libraries, String gamePath) {
  final Set<String> result = {};
  for (final lib in libraries) {
    final name = lib['name'];
    if (name is! String) continue;
    // 解析Maven坐标 group:artifact:version[:classifier]
    final parts = name.split(':');
    if (parts.length < 3) continue;
    final group = parts[0].replaceAll('.', '/');
    final artifact = parts[1];
    String version = parts[2];
    String classifier = '';
    // 处理classifier和版本
    if (parts.length > 3) {
      classifier = parts.length > 3 ? '-${parts[3]}' : '';
    }
    // 构建jar路径
    final path = normalizePath('$gamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}$group${Platform.pathSeparator}$artifact${Platform.pathSeparator}$version${Platform.pathSeparator}$artifact-$version$classifier.jar');
    if (File(path).existsSync()) {
      result.add(path);
    }
  }
  return result;
}

// assetIndex获取
Future<String?> getAssetIndex(String versionJsonPath) async {
  final file = File(versionJsonPath);
  if (!await file.exists()) return null;
  dynamic root;
  try {
    root = jsonDecode(await file.readAsString());
  } catch (_) {
    return null;
  }
  if (root is! Map) return null;
  // 优先：顶层 assetIndex.id
  final ai = root['assetIndex'];
  if (ai is Map && ai['id'] is String && (ai['id'] as String).isNotEmpty) {
    return ai['id'] as String;
  }
  // 备选：patches[].assetIndex.id
  final patches = root['patches'];
  if (patches is List) {
    for (final p in patches) {
      if (p is Map) {
        final pai = p['assetIndex'];
        final id = (pai is Map) ? pai['id'] : null;
        if (id is String && id.isNotEmpty) return id;
      }
    }
  }
  // 最后回退：assets 字段（通常等于 id）
  final assets = root['assets'];
  if (assets is String && assets.isNotEmpty) return assets;
  return null;
}

// 从jar路径提取库标识 (group:artifact)
String extractLibraryIdentifier(String jarPath) {
  final pathParts = p.split(jarPath);
  final libIndex = pathParts.indexOf('libraries');
  if (libIndex >= 0 && libIndex + 4 <= pathParts.length) {
    // groupId
    final groupPath = pathParts.sublist(libIndex + 1, pathParts.length - 3).join('.');
    // artifactId
    final artifact = pathParts[pathParts.length - 3];
    // version
    final version = pathParts[pathParts.length - 2];
    return '$groupPath:$artifact:$version';
  }
  // fallback
  return p.basename(jarPath);
}

// 加载NeoForge配置文件
Future<Map<String, dynamic>?> loadNeoForgeConfig(String gamePath, String game) async {
  final neoForgeJsonPath = '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game${Platform.pathSeparator}NeoForge.json';
  final file = File(neoForgeJsonPath);
  if (!await file.exists()) {
    debugPrint('找不到NeoForge配置: $neoForgeJsonPath');
    return null;
  }
  try {
    final jsonContent = await file.readAsString();
    final config = jsonDecode(jsonContent) as Map<String, dynamic>;
    return config;
  } catch (e) {
    debugPrint('解析NeoForge.json失败: $e');
    return null;
  }
}

// 替换配置中的变量
String replaceConfigVariables(String input, Map<String, String> variables) {
  String result = input;
  for (final entry in variables.entries) {
    result = result.replaceAll('\${${entry.key}}', entry.value);
  }
  return result;
}

Future<void> neoforgeLauncher() async {
  final prefs = await SharedPreferences.getInstance();
  // 游戏参数
  final java = prefs.getString('SelectedJavaPath') ?? 'java';
  final selectedPath = prefs.getString('SelectedPath') ?? '';
  final gamePath = prefs.getString('Path_$selectedPath') ?? '';
  final game = prefs.getString('SelectedGame') ?? '';
  final nativesPath = '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game${Platform.pathSeparator}natives';
  final version = prefs.getString('version') ?? '';
  final cfg = prefs.getStringList('Config_${selectedPath}_$game') ?? [];
  final jsonPath = '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game${Platform.pathSeparator}$game.json';
  final profilePath = '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game${Platform.pathSeparator}install_profile.json';
  // 加载NeoForge配置
  final neoForgeConfig = await loadNeoForgeConfig(gamePath, game);
  debugPrint('NeoForge配置加载${neoForgeConfig != null ? "成功" : "失败"}');
  // 变量映射，用于替换配置中的占位符
  final variables = {
    'library_directory': '$gamePath${Platform.pathSeparator}libraries',
    'classpath_separator': Platform.isWindows ? ';' : ':',
    'version_name': game,
    'natives_directory': nativesPath,
  };
  // 使用Map存储库路径，按库标识去重，确保优先使用NeoForge版本
  final Map<String, String> librariesMap = {};
  // 首先从NeoForge.json加载库
  if (neoForgeConfig != null && neoForgeConfig.containsKey('libraries')) {
    final libraries = neoForgeConfig['libraries'] as List;
    for (final lib in libraries) {
      if (lib is! Map) continue;
      final downloads = lib['downloads'];
      if (downloads is! Map) continue;
      final artifact = downloads['artifact'];
      if (artifact is! Map) continue;
      final path = artifact['path'];
      if (path is String && path.isNotEmpty) {
        final fullPath = normalizePath('$gamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}$path');
        final identifier = extractLibraryIdentifier(fullPath);
        librariesMap[identifier] = fullPath;
      }
    }
    debugPrint(librariesMap.toString());
    debugPrint('从NeoForge.json加载了 ${librariesMap.length} 个库');
  }
  final versionLibs = await loadLibraryArtifactPaths(jsonPath, gamePath);
  for (final lib in versionLibs) {
    final identifier = extractLibraryIdentifier(lib);
    librariesMap.putIfAbsent(identifier, () => lib);
  }
  final libraries = librariesMap.values.toSet();
  final separator = Platform.isWindows ? ';' : ':';
  final gameJar = normalizePath('$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game${Platform.pathSeparator}$game.jar');
  final sortedLibraries = libraries.toList()..sort();
  final classPath = sortedLibraries.join(separator);
  final cp = '$classPath$separator$gameJar';
  String mainClass = neoForgeConfig?['mainClass'] as String? ?? 'net.neoforged.fancymodloader.bootstraplauncher.BootstrapLauncher';
  debugPrint('使用mainClass: $mainClass');
  debugPrint('类路径库数量: ${libraries.length}');
  final account = prefs.getString('SelectedAccount') ?? '';
  final accountInfo = prefs.getStringList('Account_$account') ?? [];
  final assetIndex = await getAssetIndex(jsonPath) ?? '';
  // 基础JVM参数
  final jvmArgs = <String>[
    '-Xmx${cfg[0]}G',
    '-XX:+UseG1GC',
    '-Dstderr.encoding=UTF-8',
    '-Dstdout.encoding=UTF-8',
    '-XX:-OmitStackTraceInFastThrow',
    '-Dfml.ignoreInvalidMinecraftCertificates=true',
    '-Dfml.ignorePatchDiscrepancies=true',
    '-Dminecraft.launcher.brand=FML',
    if (Platform.isMacOS) '-XstartOnFirstThread',
    '-Djava.library.path=$nativesPath',
    '-Djna.tmpdir=$nativesPath',
  ];
  // 添加NeoForge.json中定义的JVM参数
  if (neoForgeConfig != null &&
      neoForgeConfig.containsKey('arguments') &&
      neoForgeConfig['arguments'] is Map &&
      neoForgeConfig['arguments'].containsKey('jvm')) {
    final jvmArgsList = neoForgeConfig['arguments']['jvm'] as List;
    for (var arg in jvmArgsList) {
      if (arg is String) {
        final processedArg = replaceConfigVariables(arg, variables);
        jvmArgs.add(processedArg);
      }
    }
    debugPrint('添加了 ${jvmArgsList.length} 个来自NeoForge.json的JVM参数');
  }
  jvmArgs.addAll(['-cp', cp]);
  final gameArgs = <String>[
    '--username', account,
    '--version', game,
    '--gameDir', '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game',
    '--assetsDir', '$gamePath${Platform.pathSeparator}assets',
    '--assetIndex', assetIndex,
    '--uuid', if (accountInfo[2] == '1') accountInfo[3] else accountInfo[0],
    '--accessToken', accountInfo[0],
    '--versionType', '"FML $version"',
    '--width', cfg[2],
    '--height', cfg[3],
    if (cfg[1] == '1') '--fullscreen'
  ];
  // 添加NeoForge.json中定义的游戏参数
  if (neoForgeConfig != null &&
      neoForgeConfig.containsKey('arguments') &&
      neoForgeConfig['arguments'] is Map &&
      neoForgeConfig['arguments'].containsKey('game')) {
    final gameArgsList = neoForgeConfig['arguments']['game'] as List;
    for (var arg in gameArgsList) {
      if (arg is String) {
        final processedArg = replaceConfigVariables(arg, variables);
        gameArgs.add(processedArg);
      }
    }
    debugPrint('添加了 ${gameArgsList.length} 个来自NeoForge.json的游戏参数');
  }
  final args = [...jvmArgs, mainClass, ...gameArgs];
  debugPrint('启动命令: ${args.join(" ")}');
  debugPrint('主类: $mainClass');
  final proc = await Process.start(java, args, workingDirectory: '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game');
  proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => debugPrint('[OUT] $l'));
  proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => debugPrint('[ERR] $l'));
  final code = await proc.exitCode;
  debugPrint('退出码: $code');
}
