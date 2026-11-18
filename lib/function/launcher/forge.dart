import 'launch_session.dart';
import 'mmc_command.dart';
import 'forge_command.dart';
export 'forge_command.dart' show buildForgeCommand;

import 'package:crypto/crypto.dart';

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:fml/function/config/app_config.dart';
import 'package:fml/function/forge/forge_metadata.dart';
import 'package:fml/function/java/java_launch_check.dart';
import 'package:fml/function/log.dart';

import 'login/microsoft_login.dart' as microsoft;
import 'login/external_login.dart' as external_login;

Future<void> forgeLauncher({
  required LaunchSession session,
  String? javaExecutable,
  void Function(String)? onProgress,
  void Function(String)? onError,
  AppConfig? configuration,
  Map? mmcProfile,
}) async {
  try {
    onProgress?.call('正在准备 Forge');
    final prefs = configuration ?? await AppConfig.getInstance();
    final selectedPath = (await prefs.getString('SelectedPath')) ?? '';
    final root = (await prefs.getString('Path_$selectedPath')) ?? '';
    final name = (await prefs.getString('SelectedGame')) ?? '';
    final instance = safeChild(p.join(root, 'versions'), name);
    final config =
        (await prefs.getStringList('Config_${selectedPath}_$name')) ?? [];
    if (config.length < 5) throw StateError('游戏配置不完整，请重新安装 Forge');
    final vanilla = jsonDecode(
      await File(p.join(instance, '$name.json')).readAsString(),
    ) as Map;
    final forge =
        mmcProfile ??
        jsonDecode(await File(p.join(instance, 'Forge.json')).readAsString())
            as Map;
    final java = javaExecutable ?? await configuredJavaExecutable(prefs);
    final libraries = <String>[];
    for (final lib
        in mmcProfile != null
            ? (mmcProfile['libraries'] as List).cast<Map>()
            : mergedLibraries(vanilla, forge)) {
      if (!rulesAllow(lib['rules'])) continue;
      final artifact = libraryArtifact(lib);
      if (artifact == null) continue;
      final local = artifact['mmcLocalPath'] as String?;
      final path = local == null
          ? safeChild(p.join(root, 'libraries'), artifact['path'])
          : safeChild(instance, local);
      if (local != null &&
          (artifact['sha1'] == null ||
              !await File(path).exists() ||
              (await sha1.bind(File(path).openRead()).first).toString() !=
                  artifact['sha1'])) {
        throw StateError('MMC 本地运行库已丢失或改变: ${lib['name']}');
      }
      if (!await File(path).exists()) {
        throw StateError('缺少运行库 ${lib['name']}，请重新安装');
      }
      libraries.add(path);
    }
    libraries.add(p.join(instance, '$name.jar'));
    final accountName = (await prefs.getString('SelectedAccountName')) ?? '';
    final type = (await prefs.getString('SelectedAccountType')) ?? '';
    final prefix = switch (type) {
      '0' => 'offline',
      '1' => 'online',
      '2' => 'external',
      _ => 'unknown',
    };
    final account =
        (await prefs.getStringList('${prefix}_account_$accountName')) ?? [];
    if (account.length <
        (type == '2'
            ? 7
            : type == '0'
            ? 4
            : 3)) {
      throw StateError('请先选择有效的游戏账号');
    }
    session.redactor.addAccount(type, account);
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
      'launcher_version': (await prefs.getString('version')) ?? '1.9.0',
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
    final args = mmcProfile == null
        ? buildForgeCommand(
            vanilla: vanilla,
            forge: forge,
            variables: variables,
            config: config,
            authlib: authlib,
          )
        : buildMmcCommand(
            profile: mmcProfile,
            variables: variables,
            config: config,
            authlib: authlib,
          );
    await session.run(
      executable: java,
      arguments: args,
      workingDirectory: instance,
      gameRoot: root,
      metadataPath: p.join(instance, '$name.json'),
      secrets: [token],
    );
  } catch (e) {
    await LogUtil.log(session.redactor.clean('Forge 启动失败: $e'), level: 'ERROR');
    onError?.call('启动 Forge 失败: $e');
  }
}
