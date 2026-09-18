import 'dart:io';

import 'package:path/path.dart' as p;

String minecraftOS([String? os]) => switch (os ?? Platform.operatingSystem) {
  'macos' => 'osx',
  final value => value,
};

/// Maven coordinates may include both a classifier and a non-JAR extension.
String mavenPath(String coordinate) {
  final extension = coordinate.split('@');
  final parts = extension.first.split(':');
  if (parts.length < 3 || parts.length > 4 || parts.any((s) => s.isEmpty)) {
    throw FormatException('无效的 Maven 坐标: $coordinate');
  }
  return '${parts[0].replaceAll('.', '/')}/${parts[1]}/${parts[2]}/'
      '${parts[1]}-${parts[2]}${parts.length == 4 ? '-${parts[3]}' : ''}.'
      '${extension.length == 2 ? extension.last : 'jar'}';
}

String safeChild(String root, String relative) {
  final normalized = relative.replaceAll('\\', '/');
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
      normalized.split('/').contains('..')) {
    throw FormatException('无效的相对路径: $relative');
  }
  final result = p.normalize(p.join(root, normalized));
  if (!p.isWithin(p.absolute(root), p.absolute(result))) {
    throw FormatException('路径超出安装目录: $relative');
  }
  return result;
}

String? instanceNameError(String name) {
  if (name.trim().isEmpty) return '请输入游戏名称';
  if (name != name.trim() ||
      name.endsWith('.') ||
      RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name) ||
      name == '.' ||
      name == '..' ||
      RegExp(
        r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)',
        caseSensitive: false,
      ).hasMatch(name)) {
    return '游戏名称包含无效字符';
  }
  return null;
}

bool rulesAllow(
  dynamic rules, {
  String? os,
  String? arch,
  String? osVersion,
  Map<String, bool> features = const {},
}) {
  if (rules is! List || rules.isEmpty) return true;
  var allowed = false;
  final currentArch =
      arch ?? (Platform.version.contains('arm64') ? 'aarch64' : 'x86_64');
  for (final rule in rules.cast<Map>()) {
    final target = rule['os'] as Map?;
    if (target != null) {
      if (target['name'] != null && target['name'] != minecraftOS(os)) continue;
      if (target['arch'] != null &&
          target['arch'] != currentArch &&
          !(target['arch'] == 'amd64' && currentArch == 'x86_64')) {
        continue;
      }
      if (target['version'] != null &&
          !RegExp(target['version'] as String)
              .hasMatch(osVersion ?? Platform.operatingSystemVersion)) {
        continue;
      }
    }
    final required = rule['features'] as Map? ?? {};
    if (required.entries.any((e) => (features[e.key] ?? false) != e.value)) {
      continue;
    }
    allowed = rule['action'] == 'allow';
  }
  return allowed;
}

String substitute(String text, Map<String, String> variables) =>
    text.replaceAllMapped(RegExp(r'\$\{([^}]+)\}'), (m) {
      final value = variables[m[1]];
      if (value == null) throw FormatException('未知启动参数: ${m[0]}');
      return value;
    });

List<String> resolveArguments(
  dynamic values,
  Map<String, String> variables, {
  String? os,
  String? arch,
  Map<String, bool> features = const {},
}) {
  final result = <String>[];
  for (final entry in values as List? ?? []) {
    if (entry is String) {
      result.add(substitute(entry, variables));
    } else if (entry is Map &&
        rulesAllow(entry['rules'], os: os, arch: arch, features: features)) {
      final value = entry['value'];
      for (final arg in value is List ? value : [value]) {
        result.add(substitute(arg as String, variables));
      }
    }
  }
  return result;
}

List<String> splitLegacyArguments(String input) =>
    RegExp(r'''"([^"]*)"|'([^']*)'|(\S+)''')
        .allMatches(input)
        .map((m) => m[1] ?? m[2] ?? m[3]!)
        .toList();

List<Map<String, dynamic>> mergedLibraries(Map vanilla, Map forge) {
  final libraries = <String, Map<String, dynamic>>{};
  for (final entry in [
    ...?vanilla['libraries'] as List?,
    ...?forge['libraries'] as List?,
  ]) {
    final lib = Map<String, dynamic>.from(entry as Map);
    final parts = (lib['name'] as String).split('@').first.split(':');
    // Loader libraries override the vanilla version, keeping classifiers distinct.
    final key = '${parts[0]}:${parts[1]}:${parts.length > 3 ? parts[3] : ''}';
    libraries[key] = lib;
  }
  return libraries.values.toList();
}

Map<String, dynamic>? libraryArtifact(Map library) {
  if (library['clientreq'] == false) return null;
  final downloads = library['downloads'] as Map?;
  if (downloads != null) {
    final artifact = downloads['artifact'];
    return artifact is Map ? Map<String, dynamic>.from(artifact) : null;
  }
  final path = mavenPath(library['name'] as String);
  final base = library['url'] as String? ?? 'https://libraries.minecraft.net/';
  return {'path': path, 'url': '${base.endsWith('/') ? base : '$base/'}$path'};
}

String resolveProcessorValue(
  String input,
  Map<String, String> data,
  String libraries,
) {
  var value = input;
  for (var i = 0; i < 10 && RegExp(r'\{[^}]+\}').hasMatch(value); i++) {
    value = value.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (m) {
      if (!data.containsKey(m[1])) throw FormatException('未知安装参数: ${m[0]}');
      return data[m[1]]!;
    });
  }
  if (RegExp(r'\{[^}]+\}').hasMatch(value)) {
    throw FormatException('循环安装参数: $input');
  }
  if (value.startsWith("'") && value.endsWith("'")) {
    return value.substring(1, value.length - 1);
  }
  if (value.startsWith('[') && value.endsWith(']')) {
    return safeChild(
      libraries,
      mavenPath(value.substring(1, value.length - 1)),
    );
  }
  return value;
}

int compareForgeVersions(String a, String b) {
  final aa = a.split(RegExp(r'[.\-]'));
  final bb = b.split(RegExp(r'[.\-]'));
  for (var i = 0; i < aa.length || i < bb.length; i++) {
    final left = i < aa.length ? aa[i] : '0';
    final right = i < bb.length ? bb[i] : '0';
    final result = int.tryParse(left) != null && int.tryParse(right) != null
        ? int.parse(left).compareTo(int.parse(right))
        : left.compareTo(right);
    if (result != 0) return result;
  }
  return 0;
}
