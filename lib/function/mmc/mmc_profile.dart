import 'dart:io';

import '../forge/forge_metadata.dart';

/// MMC formatVersion=1 的组件数组已经定义应用顺序, patch.order 仅用于旧格式迁移.
class MmcComponentSet {
  MmcComponentSet({required this.manifest, required this.patches}) {
    if (manifest['formatVersion'] != 1 || manifest['components'] is! List) {
      throw const FormatException('不支持的 MMC 组件清单');
    }
    for (final item in manifest['components'] as List) {
      if (item is! Map ||
          (item['disabled'] != null && item['disabled'] is! bool)) {
        throw const FormatException('MMC 组件格式无效');
      }
      if (item['disabled'] == true) continue;
      final uid = item['uid'];
      if (uid is! String ||
          !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(uid) ||
          versions.containsKey(uid)) {
        throw const FormatException('MMC 组件 UID 无效或重复');
      }
      final patch = patches[uid];
      final version = patch?['version'] ?? item['version'];
      if (version is! String || version.trim().isEmpty) {
        throw FormatException('MMC 组件缺少精确版本: $uid');
      }
      if (patch != null &&
          (patch['uid'] != uid || patch['formatVersion'] != 1)) {
        throw FormatException('MMC 本地补丁身份或格式不匹配: $uid');
      }
      versions[uid] = version;
    }
    if (!versions.containsKey('net.minecraft')) {
      throw const FormatException('实例缺少活动 Minecraft 组件');
    }
    if (versions.keys.where(_loaders.contains).length > 1) {
      throw const FormatException('实例包含多个活动模组加载器');
    }
  }

  final Map<String, dynamic> manifest;
  final Map<String, Map<String, dynamic>> patches;
  final Map<String, String> versions = {};
  static const _loaders = {
    'net.fabricmc.fabric-loader',
    'net.minecraftforge',
    'net.neoforged',
  };
  String get minecraft => versions['net.minecraft']!;
  String? get loaderUid => versions.keys.where(_loaders.contains).firstOrNull;
  String? get loaderVersion => versions[loaderUid];
  Map<String, String> get runtimeComponents => {
    for (final uid in ['org.lwjgl', 'org.lwjgl3'])
      if (versions.containsKey(uid)) uid: versions[uid]!,
  };

  Future<Map<String, dynamic>> resolve({
    required Future<Map<String, dynamic>> Function(String) loadJson,
    required void Function() checkCancelled,
    String? os,
    String? arch,
  }) async {
    final components = <Map<String, dynamic>>[];
    for (final entry in versions.entries) {
      checkCancelled();
      final patch =
          patches[entry.key] ??
          await loadJson(
            'https://meta.prismlauncher.org/v1/${Uri.encodeComponent(entry.key)}/${Uri.encodeComponent(entry.value)}.json',
          );
      if (patch['uid'] != entry.key ||
          patch['version'] != entry.value ||
          patch['formatVersion'] != 1) {
        throw FormatException('MMC 组件元数据与请求版本不一致: ${entry.key}');
      }
      components.add(patch);
    }
    checkCancelled();
    return composeMmcProfile(components, os: os, arch: arch);
  }
}

String mmcArchitecture([String? arch]) {
  final value =
      arch ??
      (Platform.version.contains('arm64')
          ? 'aarch64'
          : Platform.version.contains('ia32')
          ? 'x86'
          : 'x86_64');
  return switch (value) {
    'arm64' || 'aarch64' => 'arm64',
    'arm' || 'arm32' => 'arm32',
    'amd64' || 'x86_64' => 'x86_64',
    'i386' || 'i686' || 'x86' => 'x86',
    _ => value,
  };
}

String mmcPlatform({String? os, String? arch}) {
  final base = minecraftOS(os);
  final cpu = mmcArchitecture(arch);
  if (!const ['arm64', 'arm32', 'x86_64', 'x86', 'ppc64le'].contains(cpu)) {
    throw FormatException('不支持的 Java 架构: $cpu');
  }
  return cpu == 'arm64'
      ? '$base-arm64'
      : cpu == 'arm32'
      ? '$base-arm32'
      : cpu == 'ppc64le'
      ? '$base-ppc64le'
      : base;
}

/// MMC 把原生架构编码在 OS 名称中, 与 Mojang 的 os.arch 字段不同.
bool mmcRulesAllow(dynamic rules, {String? os, String? arch}) => rulesAllow(
  rules,
  os: mmcPlatform(os: os, arch: arch),
  arch: mmcArchitecture(arch) == 'arm64' ? 'aarch64' : mmcArchitecture(arch),
);

Map<String, dynamic> mmcArtifact(Map library, {String? classifier}) {
  final name = library['name'];
  if (name is! String) throw const FormatException('MMC 运行库缺少 Maven 坐标');
  final coordinate = classifier == null
      ? name
      : '${name.split(':').take(3).join(':')}:$classifier';
  final path = mavenPath(coordinate);
  safeChild('/mmc-libraries', path);
  final downloads = library['downloads'];
  final supplied = classifier == null
      ? (downloads?['artifact'])
      : (downloads?['classifiers']?[classifier]);
  if (supplied != null && supplied is! Map) {
    throw FormatException('MMC 运行库下载信息无效: $name');
  }
  final result = <String, dynamic>{
    'path': path,
    if (supplied is Map) ...Map<String, dynamic>.from(supplied),
  };
  safeChild('/mmc-libraries', result['path'] as String);
  if (library['MMC-hint'] == 'local') {
    result['mmcLocal'] = path.split('/').last;
    result.remove('url');
  } else {
    final base =
        library['url'] as String? ?? 'https://libraries.minecraft.net/';
    result['url'] ??= '${base.endsWith('/') ? base : '$base/'}$path';
    final uri = Uri.tryParse(result['url'] as String);
    if (uri == null ||
        !const ['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw FormatException('MMC 运行库 URL 无效: $name');
    }
  }
  if (result['sha1'] != null &&
      (result['sha1'] is! String ||
          !RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(result['sha1']))) {
    throw FormatException('MMC 运行库 SHA1 无效: $name');
  }
  return result;
}

Map<String, dynamic> composeMmcProfile(
  List<Map<String, dynamic>> components, {
  String? os,
  String? arch,
}) {
  final versions = {for (final c in components) c['uid']: c['version']};
  final applied = <String>{};
  final libraries = <String, Map<String, dynamic>>{};
  final jvm = <String>[];
  final tweakers = <String>[];
  final traits = <String>{};
  final java = <int>{};
  final result = <String, dynamic>{
    'fmlMmcProfileVersion': 1,
    'mmcPlatform': mmcPlatform(os: os, arch: arch),
    'mmcArch': mmcArchitecture(arch),
  };
  for (final c in components) {
    final uid = c['uid'] as String;
    if (!applied.add(uid)) throw FormatException('MMC 重复组件: $uid');
    for (final unsupported in [
      'jarMods',
      '+jarMods',
      'mods',
      '+mods',
      'agents',
      '+agents',
      'mavenFiles',
      'appletClass',
      '-libraries',
    ]) {
      if (c[unsupported] != null &&
          c[unsupported] != '' &&
          (c[unsupported] is! List || (c[unsupported] as List).isNotEmpty)) {
        throw FormatException('MMC 组件 $uid 包含尚不支持的字段: $unsupported');
      }
    }
    for (final requirement in c['requires'] as List? ?? []) {
      final dependency = requirement['uid'];
      if (!versions.containsKey(dependency) ||
          (requirement['equals'] != null &&
              versions[dependency] != requirement['equals'])) {
        throw FormatException('MMC 组件依赖不满足: $uid -> $dependency');
      }
      if (!applied.contains(dependency) || dependency == uid) {
        throw FormatException('MMC 组件顺序错误或循环依赖: $uid -> $dependency');
      }
    }
    for (final conflict in c['conflicts'] as List? ?? []) {
      if (versions.containsKey(conflict['uid']) &&
          (conflict['equals'] == null ||
              conflict['equals'] == versions[conflict['uid']])) {
        throw FormatException('MMC 组件冲突: $uid / ${conflict['uid']}');
      }
    }
    if (uid == 'net.minecraft') {
      result['id'] = c['version'];
      result['type'] = c['type'] ?? 'release';
      result['assetIndex'] = c['assetIndex'];
    }
    for (final key in ['mainClass', 'minecraftArguments']) {
      if (c[key] is String && (c[key] as String).isNotEmpty) {
        result[key] = c[key];
      }
    }
    if (c['mainJar'] is Map) {
      result['downloads'] = {'client': mmcArtifact(c['mainJar'])};
    }
    jvm.addAll(_strings(c['+jvmArgs'], '$uid +jvmArgs'));
    for (final t in _strings(c['+tweakers'], '$uid +tweakers')) {
      tweakers.remove(t);
      tweakers.add(t);
    }
    traits.addAll(_strings(c['+traits'], '$uid +traits'));
    for (final major in c['compatibleJavaMajors'] as List? ?? []) {
      if (major is! int || major < 1) {
        throw FormatException('MMC Java 兼容版本无效: $uid');
      }
      java.add(major);
    }
    for (final raw in c['libraries'] as List? ?? []) {
      final lib = Map<String, dynamic>.from(raw as Map);
      if (!mmcRulesAllow(lib['rules'], os: os, arch: arch)) continue;
      final name = lib['name'] as String;
      final parts = name.split('@').first.split(':');
      if (parts.length < 3) throw FormatException('MMC Maven 坐标无效: $name');
      final key =
          '${parts[0]}:${parts[1]}:${parts.length > 3 ? parts[3] : ''}:${name.contains('@') ? name.split('@').last : 'jar'}';
      final previous = libraries[key];
      if (previous != null &&
          compareForgeVersions(
                parts[2],
                (previous['name'] as String).split(':')[2],
              ) <=
              0) {
        continue;
      }
      // 先按平台选原生分类, 再转成现有下载器可消费的 Mojang 结构.
      final artifacts = <String, dynamic>{};
      if (lib['downloads'] == null || lib['downloads']['artifact'] != null) {
        artifacts['artifact'] = mmcArtifact(lib);
      }
      final nativeMap = lib['natives'] as Map?;
      final native = nativeMap?[mmcPlatform(os: os, arch: arch)];
      if (native != null) {
        final classifier = (native as String).replaceAll(
          r'${arch}',
          mmcArchitecture(arch) == 'x86' ? '32' : '64',
        );
        artifacts['classifiers'] = {
          classifier: mmcArtifact(lib, classifier: classifier),
        };
        lib['natives'] = {minecraftOS(os): classifier};
      } else {
        lib.remove('natives');
      }
      lib.remove('rules');
      lib['downloads'] = artifacts;
      libraries[key] = lib;
    }
  }
  if (traits.any((t) => t != 'FirstThreadOnMacOS')) {
    throw FormatException('尚不支持的 MMC 启动 trait: ${traits.join(', ')}');
  }
  if (result['id'] == null ||
      result['mainClass'] == null ||
      result['downloads'] == null ||
      result['assetIndex'] is! Map ||
      result['minecraftArguments'] is! String) {
    throw const FormatException('MMC 组件缺少完整的游戏启动元数据');
  }
  result['libraries'] = libraries.values.toList();
  result['mmcTweakers'] = tweakers;
  result['mmcTraits'] = traits.toList();
  result['arguments'] = {'jvm': jvm};
  if (java.isNotEmpty) result['compatibleJavaMajors'] = java.toList();
  result['mmcComponents'] = versions;
  return result;
}

List<String> _strings(dynamic value, String field) {
  if (value == null) return [];
  if (value is! List || value.any((v) => v is! String)) {
    throw FormatException('MMC $field 必须是字符串数组');
  }
  return value.cast<String>();
}
