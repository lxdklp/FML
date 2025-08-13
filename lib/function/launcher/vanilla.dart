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

Future<void> vanillaLauncher() async {
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
  final assetIndex = await getAssetIndex(jsonPath) ?? '';final cp = '$classPath$separator$gameJar';
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
    '-cp', cp,
    'net.minecraft.client.main.Main',
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
  debugPrint(args.join("\n"));
  final proc = await Process.start(java, args);
  proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => debugPrint('[OUT] $l'));
  proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) => debugPrint('[ERR] $l'));
  final code = await proc.exitCode;
  debugPrint('退出码: $code');
}
