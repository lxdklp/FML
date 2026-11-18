import 'forge_command.dart';

List<String> buildMmcCommand({
  required Map profile,
  required Map<String, String> variables,
  required List<String> config,
  String? os,
  String? arch,
  String? authlib,
}) {
  if (profile['fmlMmcProfileVersion'] != 1) {
    throw const FormatException('MMC 启动配置版本无效');
  }
  final arguments = buildForgeCommand(
    vanilla: profile,
    forge: {
      'mainClass': profile['mainClass'],
      'minecraftArguments': profile['minecraftArguments'],
    },
    variables: variables,
    config: config,
    os: os,
    arch: arch,
    authlib: authlib,
    firstThread: (profile['mmcTraits'] as List? ?? []).contains(
      'FirstThreadOnMacOS',
    ),
  );
  for (final tweaker in profile['mmcTweakers'] as List? ?? []) {
    arguments.addAll(['--tweakClass', tweaker as String]);
  }
  return arguments;
}
