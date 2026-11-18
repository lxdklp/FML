import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import '../java/java_launch_check.dart';
import '../java/java_utils.dart';
import '../mmc/mmc_profile.dart';
import 'forge.dart';
import 'launch_session.dart';
export 'mmc_command.dart' show buildMmcCommand;

Future<void> mmcLauncher({
  required LaunchSession session,
  String? javaExecutable,
  void Function(String)? onProgress,
  void Function(String)? onError,
  AppConfig? configuration,
}) async {
  try {
    final prefs = configuration ?? await AppConfig.getInstance();
    final pathName = await prefs.getString('SelectedPath') ?? '';
    final root = await prefs.getString('Path_$pathName') ?? '';
    final name = await prefs.getString('SelectedGame') ?? '';
    final profile = jsonDecode(
      await File(p.join(root, 'versions', name, 'fml-mmc-profile.json'))
          .readAsString(),
    ) as Map;
    final java = javaExecutable ?? await configuredJavaExecutable(prefs);
    final arch = await JavaUtils.probeJavaArchitecture(java);
    if (arch == null) throw StateError('无法识别 MMC 实例使用的 Java 架构');
    if (profile['mmcPlatform'] != mmcPlatform(arch: arch) ||
        profile['mmcArch'] != mmcArchitecture(arch)) {
      throw StateError('当前 Java 的平台或架构与已安装的 MMC 运行库不同, 请使用安装时的 Java 架构或重新导入');
    }
    await forgeLauncher(
      session: session,
      javaExecutable: java,
      onProgress: onProgress,
      onError: onError,
      configuration: prefs,
      mmcProfile: profile,
    );
  } catch (error) {
    onError?.call('MMC 启动失败: $error');
    if (onError == null) rethrow;
  }
}
