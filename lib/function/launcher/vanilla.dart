import 'dart:io';
import 'package:fml/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:fml/function/log.dart';
import 'package:fml/function/launcher/login/microsoft_login.dart'
    as microsoft_login;
import 'package:fml/function/launcher/login/external_login.dart'
    as external_login;

typedef ProgressCallback = void Function(String message);
typedef ErrorCallback = void Function(String error);
// library获取
Future<List<String>> loadLibraryArtifactPaths(
  String versionJsonPath,
  String gamePath,
) async {
  final file = File(versionJsonPath);
  if (!await file.exists()) return [];
  late final dynamic root;
  try {
    root = jsonDecode(await file.readAsString());
  } catch (e) {
    LogUtil.log('JSON 解析失败: $e', level: 'ERROR');
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
      final fullPath =
          '$gamePath${Platform.pathSeparator}libraries${Platform.pathSeparator}$path';
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
  final assets = root['assets'];
  if (assets is String && assets.isNotEmpty) return assets;
  return null;
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

// 启动Vanilla
Future<void> vanillaLauncher({
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
  final libraries = await loadLibraryArtifactPaths(jsonPath, gamePath);
  final separator = Platform.isWindows ? ';' : ':';
  final classPath = libraries.join(separator);
  final gameJar =
      '$gamePath${Platform.pathSeparator}versions${Platform.pathSeparator}$game${Platform.pathSeparator}$game.jar';
  final assetIndex = await getAssetIndex(jsonPath) ?? '';
  final cp = '$classPath$separator$gameJar';
  final accountName = prefs.getString('SelectedAccountName') ?? '';
  final accountType = prefs.getString('SelectedAccountType') ?? '';
  final accountInfo =
      prefs.getStringList(
        '${_getLoginMode(accountType)}_account_$accountName',
      ) ??
      [];
  // 账号信息
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
  // 启动参数
  onProgress?.call('正在准备启动参数');
  final args = <String>[
    '-Xmx${cfg[0]}M',
    '-XX:+UseG1GC',
    '-XX:-OmitStackTraceInFastThrow',
    '-Dfml.ignoreInvalidMinecraftCertificates=true',
    '-Dfml.ignorePatchDiscrepancies=true',
    '-Dminecraft.launcher.brand=FML',
    if (Platform.isMacOS) '-XstartOnFirstThread',
    '-Djava.library.path=$nativesPath',
    '-Djna.tmpdir=$nativesPath',
    if (accountInfo[0] == '2')
      '-javaagent:$gamePath${Platform.pathSeparator}authlib-injector.jar=${accountInfo[2]}',
    '-cp',
    cp,
    'net.minecraft.client.main.Main',
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
    '"$kAppNameAbb $version"',
    '--xuid',
    '"\${auth_xuid}"',
    '--width',
    cfg[2],
    '--height',
    cfg[3],
    if (cfg[1] == '1') '--fullscreen',
  ];
  LogUtil.log('使用的Java: $java', level: 'INFO');
  onProgress?.call('正在启动游戏');
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
}
