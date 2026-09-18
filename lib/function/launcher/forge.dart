import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fml/function/forge/forge_metadata.dart';
import 'package:fml/function/java/java_launch_check.dart';
import 'package:fml/function/log.dart';

import 'login/microsoft_login.dart' as microsoft;
import 'login/external_login.dart' as external_login;

/// Builds an argument vector, never a shell command (paths may contain spaces).
List<String> buildForgeCommand({
  required Map vanilla,
  required Map forge,
  required Map<String, String> variables,
  required List<String> config,
  String? os,
  String? arch,
  String? authlib,
}) {
  final features = {'has_custom_resolution': true};
  final jvm = <String>[
    '-Xmx${config[0]}M',
    if (minecraftOS(os) == 'osx') '-XstartOnFirstThread',
    '-Djava.library.path=${variables['natives_directory']}',
    '-Djna.tmpdir=${variables['natives_directory']}',
    ?authlib,
  ];
  jvm.addAll(
    resolveArguments(
      vanilla['arguments']?['jvm'],
      variables,
      os: os,
      arch: arch,
      features: features,
    ),
  );
  jvm.addAll(
    resolveArguments(
      forge['arguments']?['jvm'],
      variables,
      os: os,
      arch: arch,
      features: features,
    ),
  );
  if (!jvm.contains('-cp') &&
      !jvm.contains('-classpath') &&
      !jvm.contains('--class-path')) {
    jvm.addAll(['-cp', variables['classpath']!]);
  }
  final game = <String>[];
  final loggingArgument = vanilla['logging']?['client']?['argument'] as String?;
  if (loggingArgument != null) jvm.add(substitute(loggingArgument, variables));
  final legacy = forge['minecraftArguments'] ?? vanilla['minecraftArguments'];
  if (forge['minecraftArguments'] != null || vanilla['arguments'] == null) {
    if (legacy is! String) throw const FormatException('缺少游戏启动参数');
    game.addAll(
      splitLegacyArguments(legacy).map((v) => substitute(v, variables)),
    );
    if (forge['minecraftArguments'] == null) {
      game.addAll(
        resolveArguments(
          forge['arguments']?['game'],
          variables,
          os: os,
          arch: arch,
          features: features,
        ),
      );
    }
  } else {
    game.addAll(
      resolveArguments(
        vanilla['arguments']?['game'],
        variables,
        os: os,
        arch: arch,
        features: features,
      ),
    );
    game.addAll(
      resolveArguments(
        forge['arguments']?['game'],
        variables,
        os: os,
        arch: arch,
        features: features,
      ),
    );
  }
  if (!game.contains('--width')) game.addAll(['--width', config[2]]);
  if (!game.contains('--height')) game.addAll(['--height', config[3]]);
  if (config[1] == '1') game.add('--fullscreen');
  final main = forge['mainClass'] as String?;
  if (main == null || main.isEmpty) {
    throw const FormatException('Forge 配置缺少启动主类');
  }
  return [...jvm, main, ...game];
}

Future<void> forgeLauncher({
  String? javaExecutable,
  void Function(String)? onProgress,
  void Function(String)? onError,
}) async {
  try {
    onProgress?.call('正在准备 Forge');
    final prefs = await SharedPreferences.getInstance();
    final selectedPath = prefs.getString('SelectedPath') ?? '';
    final root = prefs.getString('Path_$selectedPath') ?? '';
    final name = prefs.getString('SelectedGame') ?? '';
    final instance = safeChild(p.join(root, 'versions'), name);
    final config = prefs.getStringList('Config_${selectedPath}_$name') ?? [];
    if (config.length < 5) throw StateError('游戏配置不完整，请重新安装 Forge');
    final vanilla = jsonDecode(
      await File(p.join(instance, '$name.json')).readAsString(),
    ) as Map;
    final forge = jsonDecode(
      await File(p.join(instance, 'Forge.json')).readAsString(),
    ) as Map;
    final java = javaExecutable ?? configuredJavaExecutable(prefs);
    final libraries = <String>[];
    for (final lib in mergedLibraries(vanilla, forge)) {
      if (!rulesAllow(lib['rules'])) continue;
      final artifact = libraryArtifact(lib);
      if (artifact == null) continue;
      final path = safeChild(p.join(root, 'libraries'), artifact['path']);
      if (!await File(path).exists()) {
        throw StateError('缺少运行库 ${lib['name']}，请重新安装');
      }
      libraries.add(path);
    }
    libraries.add(p.join(instance, '$name.jar'));
    final accountName = prefs.getString('SelectedAccountName') ?? '';
    final type = prefs.getString('SelectedAccountType') ?? '';
    final prefix = switch (type) {
      '0' => 'offline',
      '1' => 'online',
      '2' => 'external',
      _ => 'unknown',
    };
    final account = prefs.getStringList('${prefix}_account_$accountName') ?? [];
    if (account.length <
        (type == '2'
            ? 7
            : type == '0'
            ? 4
            : 3)) {
      throw StateError('请先选择有效的游戏账号');
    }
    var uuid = account[1];
    var token = '0';
    String? authlib;
    onProgress?.call('正在验证账号');
    if (type == '0') {
      if (account[2] == '1') uuid = account[3];
    } else if (type == '1') {
      token = await microsoft.login(account[2]);
      if (token.isEmpty) throw StateError('正版账号登录失败，请重新登录账号');
    } else if (type == '2') {
      if (!await external_login.checkAuthlibInjector(root)) {
        await external_login.downloadAuthlibInjector(root);
      }
      if (!await File(p.join(root, 'authlib-injector.jar')).exists()) {
        throw StateError('AuthlibInjector 下载失败');
      }
      token =
          await external_login.checkToken(account[2], account[5], account[6])
          ? account[5]
          : await external_login.refreshToken(
              account[2],
              account[5],
              account[6],
              accountName,
              uuid,
            );
      if (token.isEmpty) throw StateError('外置账号登录失败，请重新登录账号');
      authlib =
          '-javaagent:${p.join(root, 'authlib-injector.jar')}=${account[2]}';
    } else {
      throw StateError('不支持的账号类型');
    }
    final assets = p.join(root, 'assets');
    final assetId = vanilla['assetIndex']?['id'] ?? vanilla['assets'] ?? '';
    final variables = <String, String>{
      'auth_player_name': accountName,
      'auth_uuid': uuid,
      'auth_access_token': token,
      'auth_session': 'token:$token:$uuid',
      'user_type': type == '1' ? 'msa' : 'legacy',
      'user_properties': '{}',
      'profile_properties': '{}',
      'version_name': name,
      'version_type': 'Forge',
      'game_directory': instance,
      'assets_root': assets,
      'assets_index_name': assetId,
      'game_assets': p.join(assets, 'virtual', assetId),
      'natives_directory': p.join(instance, 'natives'),
      'library_directory': p.join(root, 'libraries'),
      'classpath_separator': Platform.isWindows ? ';' : ':',
      'classpath': libraries.join(Platform.isWindows ? ';' : ':'),
      'launcher_name': 'FML',
      'launcher_version': prefs.getString('version') ?? '1.9.0',
      'resolution_width': config[2],
      'resolution_height': config[3],
      'clientid': '',
      'auth_xuid': '',
      if (vanilla['logging']?['client']?['file']?['id'] != null)
        'path': safeChild(
          p.join(root, 'assets', 'log_configs'),
          vanilla['logging']['client']['file']['id'],
        ),
    };
    final args = buildForgeCommand(
      vanilla: vanilla,
      forge: forge,
      variables: variables,
      config: config,
      authlib: authlib,
    );
    onProgress?.call('正在启动 Forge');
    final process = await Process.start(java, args, workingDirectory: instance);
    final log = File(p.join(instance, 'forge-launch.log')).openWrite();
    void writeLine(String line) =>
        log.writeln(token == '0' ? line : line.replaceAll(token, '[REDACTED]'));
    final output = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach(writeLine);
    final errors = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach(writeLine);
    onProgress?.call('游戏启动完成');
    final code = await process.exitCode;
    await Future.wait([output, errors]);
    await log.close();
    await LogUtil.log('Forge 退出码: $code');
    if (code != 0) onError?.call('Forge 异常退出（$code），详见版本目录内 forge-launch.log');
  } catch (e) {
    await LogUtil.log('Forge 启动失败: $e', level: 'ERROR');
    onError?.call('启动 Forge 失败: $e');
  }
}
