import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'dart:async';
import 'package:fml/function/log.dart';
import 'package:fml/function/launcher/login/microsoft_login.dart'
    as microsoft_login;
import 'package:fml/function/launcher/login/external_login.dart'
    as external_login;

typedef ProgressCallback = void Function(String message);
typedef ErrorCallback = void Function(String error);

// library获取
Future<Set<String>> loadLibraryArtifactPaths(
  String versionJsonPath,
  String gamePath,
) async {
  final file = File(versionJsonPath);
  if (!await file.exists()) return {};
  late final dynamic root;
  try {
    root = jsonDecode(await file.readAsString());
  } catch (e) {
    LogUtil.log('JSON 解析失败: $e', level: 'ERROR');
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
      final fullPath = normalizePath(
        '$gamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}$path',
      );
      result.add(fullPath);
    }
  }
  return result;
}

String normalizePath(String path) {
  return p.normalize(path);
}

// 直接从库名称构建路径
Set<String> buildLibraryPaths(
  List<Map<String, dynamic>> libraries,
  String gamePath,
) {
  final Set<String> result = {};
  for (final lib in libraries) {
    final name = lib['name'];
    if (name is! String) continue;
    final parts = name.split(':');
    if (parts.length < 3) continue;
    final group = parts[0].replaceAll('.', '/');
    final artifact = parts[1];
    String version = parts[2];
    String classifier = '';
    if (parts.length > 3) {
      classifier = parts.length > 3 ? '-${parts[3]}' : '';
    }
    // 构建jar路径
    final path = normalizePath(
      '$gamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}$group${Platform.pathSeparator}$artifact${Platform.pathSeparator}$version${Platform.pathSeparator}$artifact-$version$classifier.jar',
    );
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
  final ai = root['assetIndex'];
  if (ai is Map && ai['id'] is String && (ai['id'] as String).isNotEmpty) {
    return ai['id'] as String;
  }
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
    final groupPath = pathParts
        .sublist(libIndex + 1, pathParts.length - 3)
        .join('.');
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
Future<Map<String, dynamic>?> loadNeoForgeConfig(
  String gamePath,
  String game,
) async {
  final neoForgeJsonPath =
      '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game${Platform.pathSeparator}NeoForge.json';
  final file = File(neoForgeJsonPath);
  if (!await file.exists()) {
    LogUtil.log('找不到NeoForge配置: $neoForgeJsonPath', level: 'ERROR');
    return null;
  }
  try {
    final jsonContent = await file.readAsString();
    final config = jsonDecode(jsonContent) as Map<String, dynamic>;
    return config;
  } catch (e) {
    LogUtil.log('解析NeoForge.json失败: $e', level: 'ERROR');
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

// 登录模式
String _getLoginMode(String loginMode) {
  switch (loginMode) {
    case '0':
      return 'offline';
    case '1':
      return 'online';
    case '2':
      return 'external';
    default:
      return 'unknown';
  }
}

// 启动NeoForge
Future<void> neoforgeLauncher({
  ProgressCallback? onProgress,
  ErrorCallback? onError,
}) async {
  onProgress?.call('正在准备启动');
  final prefs = await SharedPreferences.getInstance();
  // 游戏参数
  final java = prefs.getString('java') ?? 'java';
  final selectedPath = prefs.getString('SelectedPath') ?? '';
  final gamePath = prefs.getString('Path_$selectedPath') ?? '';
  final game = prefs.getString('SelectedGame') ?? '';
  final nativesPath =
      '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game${Platform.pathSeparator}natives';
  final version = prefs.getString('version') ?? '';
  final cfg = prefs.getStringList('Config_${selectedPath}_$game') ?? [];
  final jsonPath =
      '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game${Platform.pathSeparator}$game.json';
  final neoForgeConfig = await loadNeoForgeConfig(gamePath, game);
  LogUtil.log(
    'NeoForge配置加载${neoForgeConfig != null ? "成功" : "失败"}',
    level: 'INFO',
  );
  final variables = {
    'library_directory': '$gamePath${Platform.pathSeparator}libraries',
    'classpath_separator': Platform.isWindows ? ';' : ':',
    'version_name': game,
    'natives_directory': nativesPath,
  };
  final Map<String, String> librariesMap = {};
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
        final fullPath = normalizePath(
          '$gamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}$path',
        );
        final identifier = extractLibraryIdentifier(fullPath);
        librariesMap[identifier] = fullPath;
      }
    }
    LogUtil.log(librariesMap.toString(), level: 'INFO');
    LogUtil.log('从NeoForge.json加载了 ${librariesMap.length} 个库', level: 'INFO');
  }
  final versionLibs = await loadLibraryArtifactPaths(jsonPath, gamePath);
  for (final lib in versionLibs) {
    final identifier = extractLibraryIdentifier(lib);
    librariesMap.putIfAbsent(identifier, () => lib);
  }
  final libraries = librariesMap.values.toSet();
  final separator = Platform.isWindows ? ';' : ':';
  final gameJar = normalizePath(
    '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game${Platform.pathSeparator}$game.jar',
  );
  final sortedLibraries = libraries.toList()..sort();
  final classPath = sortedLibraries.join(separator);
  final cp = '$classPath$separator$gameJar';
  String mainClass =
      neoForgeConfig?['mainClass'] as String? ??
      'net.neoforged.fancymodloader.bootstraplauncher.BootstrapLauncher';
  LogUtil.log('使用mainClass: $mainClass', level: 'INFO');
  LogUtil.log('类路径库数量: ${libraries.length}', level: 'INFO');
  // 账号信息
  final accountName = prefs.getString('SelectedAccountName') ?? '';
  final accountType = prefs.getString('SelectedAccountType') ?? '';
  final accountInfo =
      prefs.getStringList(
        '${_getLoginMode(accountType)}_account_$accountName',
      ) ??
      [];
  final assetIndex = await getAssetIndex(jsonPath) ?? '';
  // 基础JVM参数
  final jvmArgs = <String>[
    '-Xmx${cfg[0]}M',
    '-XX:+UseG1GC',
    '-Dstderr.encoding=UTF-8',
    '-Dstdout.encoding=UTF-8',
    '-XX:-OmitStackTraceInFastThrow',
    '-Dfml.ignoreInvalidMinecraftCertificates=true',
    '-Dfml.ignorePatchDiscrepancies=true',
    '-Dminecraft.launcher.brand=FML',
    if (Platform.isMacOS) '-XstartOnFirstThread',
    if (accountInfo[0] == '2')
      '-javaagent:$gamePath${Platform.pathSeparator}authlib-injector.jar=${accountInfo[2]}',
    '-Djava.library.path=$nativesPath',
    '-Djna.tmpdir=$nativesPath',
  ];
  // 添加NeoForge.json中定义的JVM参数
  onProgress?.call('正在获取Neoforge参数');
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
    LogUtil.log(
      '添加了 ${jvmArgsList.length} 个来自NeoForge.json的JVM参数',
      level: 'INFO',
    );
  }
  String uuid = '';
  String token = '';
  onProgress?.call('正在获取账号信息');
  if (accountInfo[0] == '0') {
    if (accountInfo[2] == '1') {
      uuid = accountInfo[3];
    } else {
      uuid = accountInfo[1];
    }
  }
  if (accountInfo[0] == '1') {
    uuid = accountInfo[1];
    token = await microsoft_login.login(accountInfo[2]);
  }
  if (accountInfo[0] == '2') {
    if (await external_login.checkAuthlibInjector(gamePath)) {
      onProgress?.call('AuthlibInjector已存在');
    } else {
      onProgress?.call('正在下载AuthlibInjector');
      await external_login.downloadAuthlibInjector(gamePath);
    }
    uuid = accountInfo[1];
    onProgress?.call('正在检查令牌');
    if (await external_login.checkToken(
      accountInfo[2],
      accountInfo[5],
      accountInfo[6],
    )) {
      token = accountInfo[5];
    } else {
      token = await external_login.refreshToken(
        accountInfo[2],
        accountInfo[5],
        accountInfo[6],
        accountName,
        uuid,
      );
    }
  }
  jvmArgs.addAll(['-cp', cp]);
  onProgress?.call('正在准备启动参数');
  final gameArgs = <String>[
    '--username',
    accountName,
    '--version',
    game,
    '--gameDir',
    '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game',
    '--assetsDir',
    '$gamePath${Platform.pathSeparator}assets',
    '--assetIndex',
    assetIndex,
    '--uuid',
    uuid,
    if (accountInfo[0] == '0') '--accessToken',
    accountInfo[0],
    if (accountInfo[0] == '0') '--clientId',
    '"\${clientid}"',
    if (accountInfo[0] == '1' || accountInfo[0] == '2') '--accessToken',
    token,
    if (accountInfo[0] == '1' || accountInfo[0] == '2') '--userType',
    'mojang',
    if (accountInfo[0] == '2') '--clientId',
    token,
    '--versionType',
    '"FML $version"',
    '--width',
    cfg[2],
    '--height',
    cfg[3],
    if (cfg[1] == '1') '--fullscreen',
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
  }
  final args = [...jvmArgs, mainClass, ...gameArgs];
  LogUtil.log('使用的Java: $java', level: 'INFO');
  onProgress?.call('正在启动游戏');
  try {
    final out = await Process.start(
      java,
      args,
      workingDirectory:
          '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game',
    );
    out.stdout.listen((_) {});
    out.stderr.listen((_) {});
    onProgress?.call('游戏启动完成');
    final code = await out.exitCode;
    LogUtil.log('退出码: $code', level: 'INFO');
  } catch (e) {
    LogUtil.log('启动游戏进程失败: $e', level: 'ERROR');
    onError?.call('启动游戏失败: $e');
    return;
  }
}
