import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/material.dart';

// library获取
Future<List<String>> loadLibraryArtifactPaths(String versionJsonPath, String gamePath) async {
  final file = File(versionJsonPath);
  if (!await file.exists()) return [];
  late final dynamic root;
  try {
    root = jsonDecode(await file.readAsString());
  } catch (e) {
    debugPrint('JSON 解析失败: $e');
    return [];
  }
  final libs = root is Map ? root['libraries'] : null;
  if (libs is! List) return [];
  final List<String> result = [];
  for (final item in libs) {
    if (item is! Map) continue;
    final downloads = item['downloads'];
    if (downloads is! Map) continue;
    final artifact = downloads['artifact'];
    if (artifact is! Map) continue;
    final path = artifact['path'];
    if (path is String && path.isNotEmpty) {
      // 排除冲突的ASM组件
      if (path.contains('org/ow2/asm/asm')) {
        debugPrint('排除冲突的ASM组件: $path');
        continue;
      }
      final fullPath = '${gamePath}${Platform.pathSeparator}libraries${Platform.pathSeparator}${path}';
      result.add(fullPath);
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

// fabric相关
Future<Map<String, dynamic>> getFabricInfo(String path) async {
  final file = File(path);
  if (!await file.exists()) return {'game': null, 'fabric': null, 'mixin': null, 'libraries': <String>[]};

  dynamic root;
  try {
    root = jsonDecode(await file.readAsString());
  } catch (_) {
    return {'game': null, 'fabric': null, 'mixin': null, 'libraries': <String>[]};
  }
  if (root is! Map) return {'game': null, 'fabric': null, 'mixin': null, 'libraries': <String>[]};

  final patches = root['patches'];
  if (patches is! List) return {'game': null, 'fabric': null, 'mixin': null, 'libraries': <String>[]};

  String? gameVer;
  String? fabricVer;
  String? mixin;
  final List<String> fabricLibraries = [];

  String? readVersion(Map m) {
    String? s;
    if (m['version'] is String && (m['version'] as String).isNotEmpty) s = m['version'] as String;
    s ??= (m['versionId'] is String && (m['versionId'] as String).isNotEmpty) ? m['versionId'] as String : null;
    s ??= (m['ver'] is String && (m['ver'] as String).isNotEmpty) ? m['ver'] as String : null;
    final meta = m['metadata'];
    if (s == null && meta is Map && meta['version'] is String && (meta['version'] as String).isNotEmpty) {
      s = meta['version'] as String;
    }
    return s;
  }

  for (final p in patches) {
    if (p is! Map) continue;
    final id = p['id'];
    if (id is! String) continue;

    // 读取游戏与加载器版本
    final v = readVersion(p);
    if (id == 'game') {
      gameVer ??= v;
    } else if (id == 'fabric') {
      fabricVer ??= v;

      // 在 fabric 补丁的 libraries 中查找 sponge-mixin 和其他依赖库
      final libs = p['libraries'];
      if (libs is List) {
        for (final lib in libs) {
          if (lib is Map && lib['name'] is String) {
            final name = lib['name'] as String;
            // 解析Maven坐标
            final parts = name.split(':');
            if (parts.length >= 3) {
              final groupId = parts[0].replaceAll('.', Platform.pathSeparator);
              final artifactId = parts[1];
              final version = parts[2];
              final jarPath = '$groupId${Platform.pathSeparator}$artifactId${Platform.pathSeparator}$version${Platform.pathSeparator}$artifactId-$version.jar';
              fabricLibraries.add(jarPath);
            }
            if (name.contains('net.fabricmc:sponge-mixin')) {
              mixin = name.substring(26);
            }
          }
        }
      }
    }
  }
  return {
    'game': gameVer,
    'fabric': fabricVer,
    'mixin': mixin,
    'libraries': fabricLibraries
  };
}

Future<void> fabricLauncher() async {
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
  final libraries = await loadLibraryArtifactPaths(jsonPath, gamePath);
  final separator = Platform.isWindows ? ';' : ':';
  final classPath = libraries.join(separator);
  final gameJar = '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game${Platform.pathSeparator}$game.jar';
  final account = prefs.getString('SelectedAccount') ?? '';
  final accountInfo = prefs.getStringList('Account_$account') ?? [];
  final assetIndex = await getAssetIndex(jsonPath) ?? '';
  final fabricInfo = await getFabricInfo(jsonPath);
  final Map<String, String> fabricAsmVersions = {};
  for (final lib in (fabricInfo['libraries'] as List<String>? ?? [])) {
    if (lib.contains('org${Platform.pathSeparator}ow2${Platform.pathSeparator}asm')) {
      // 解析ASM组件名称和版本
      final parts = lib.split(Platform.pathSeparator);
      if (parts.length >= 4) {
        final artifactId = parts[parts.length - 2];
        final version = parts[parts.length - 3];
        fabricAsmVersions[artifactId] = version;
        debugPrint('Fabric提供的ASM组件: $artifactId 版本: $version');
      }
    }
  }
  // 基础路径
  final fabricLoader = '$gamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}net${Platform.pathSeparator}fabricmc${Platform.pathSeparator}fabric-loader${Platform.pathSeparator}${fabricInfo['fabric'] ?? ''}${Platform.pathSeparator}fabric-loader-${fabricInfo['fabric'] ?? ''}.jar';
  final intermediary = '$gamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}net${Platform.pathSeparator}fabricmc${Platform.pathSeparator}intermediary${Platform.pathSeparator}${fabricInfo['game'] ?? ''}${Platform.pathSeparator}intermediary-${fabricInfo['game'] ?? ''}.jar';
  final spongeMixin = '$gamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}net${Platform.pathSeparator}fabricmc${Platform.pathSeparator}sponge-mixin${Platform.pathSeparator}${fabricInfo['mixin'] ?? ''}${Platform.pathSeparator}sponge-mixin-${fabricInfo['mixin'] ?? ''}.jar';
  // 构建Fabric依赖库路径
  final List<String> fabricLibraryPaths = [];
  for (final lib in (fabricInfo['libraries'] as List<String>? ?? [])) {
    fabricLibraryPaths.add('$gamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}$lib');
  }
  
  // 过滤原版库中与Fabric提供的ASM组件冲突的版本
  final List<String> filteredLibraries = [];
  for (final lib in libraries) {
    bool shouldExclude = false;
    
    // 检查是否是ASM组件
    if (lib.contains('${Platform.pathSeparator}org${Platform.pathSeparator}ow2${Platform.pathSeparator}asm${Platform.pathSeparator}')) {
      for (final asmComponent in fabricAsmVersions.keys) {
        // 如果路径中包含ASM组件名称
        if (lib.contains('${Platform.pathSeparator}$asmComponent${Platform.pathSeparator}')) {
          // 检查版本是否不同于Fabric提供的版本
          final libParts = lib.split(Platform.pathSeparator);
          for (int i = 0; i < libParts.length - 1; i++) {
            if (libParts[i] == asmComponent && i > 0) {
              final version = libParts[i-1];
              if (version != fabricAsmVersions[asmComponent]) {
                shouldExclude = true;
                debugPrint('排除冲突的ASM组件: $lib (版本 $version 与Fabric提供的版本 ${fabricAsmVersions[asmComponent]} 冲突)');
                break;
              }
            }
          }
          break;
        }
      }
    }
    
    if (!shouldExclude) {
      filteredLibraries.add(lib);
    }
  }
  
  // 添加所有依赖库到类路径
  var cp = filteredLibraries.join(separator);
  cp += '$separator$gameJar$separator$fabricLoader$separator$intermediary$separator$spongeMixin';
  for (final lib in fabricLibraryPaths) {
    cp += '$separator$lib';
  }
  // 检查关键文件是否存在
  debugPrint('Fabric Loader 文件存在: ${File(fabricLoader).existsSync()}');
  debugPrint('Intermediary 文件存在: ${File(intermediary).existsSync()}');
  debugPrint('Sponge Mixin 文件存在: ${File(spongeMixin).existsSync()}');
  final args = <String>[
    '-Xmx${cfg[0]}G',
    '-XX:+UseG1GC',
    '-XX:-OmitStackTraceInFastThrow',
    '-Dfml.ignoreInvalidMinecraftCertificates=true',
    '-Dfml.ignorePatchDiscrepancies=true',
    '-Dminecraft.launcher.brand=FML',
    if (Platform.isMacOS) '-XstartOnFirstThread',
    '-Djava.library.path=$nativesPath',
    '-Djna.tmpdir=$nativesPath',
    '-Dfabric.gameDir=$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game',
    '-Dfabric.modsDir=$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game${Platform.pathSeparator}mods',
    '-cp', cp,
    'net.fabricmc.loader.impl.launch.knot.KnotClient',
    '--username', account,
    '--version', game,
    '--gameDir', gamePath,
    '--assetsDir', '$gamePath${Platform.pathSeparator}assets',
    '--assetIndex', assetIndex,
    '--uuid', if (accountInfo[2] == '1') accountInfo[3] else accountInfo[0],
    '--accessToken', accountInfo[0],
    '--versionType', '"FML $version"',
    '--xuid', '"\${auth_xuid}"',
    '--clientId', '"\${clientid}"',
    '--width', cfg[2],
    '--height', cfg[3],
    if (cfg[1] == '1') '--fullscreen'
  ];
  debugPrint('fab=$fabricLoader, sponge=$spongeMixin ,intermediary=$intermediary');
  debugPrint(args.join("\n"));
  final proc = await Process.start(java, args);
  proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => debugPrint('[OUT] $l'));
  proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => debugPrint('[ERR] $l'));
  final code = await proc.exitCode;
  debugPrint('退出码: $code');
}
