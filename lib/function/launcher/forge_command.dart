import '../forge/forge_metadata.dart';

/// 构造参数数组, 带空格的路径不会经过 shell 解析.
List<String> buildForgeCommand({
  required Map vanilla,
  required Map forge,
  required Map<String, String> variables,
  required List<String> config,
  String? os,
  String? arch,
  String? authlib,
  bool firstThread = true,
}) {
  final features = {'has_custom_resolution': true};
  final jvm = <String>[
    '-Xmx${config[0]}M',
    if (firstThread && minecraftOS(os) == 'osx') '-XstartOnFirstThread',
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
