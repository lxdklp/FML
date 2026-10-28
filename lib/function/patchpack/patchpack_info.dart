import 'maven_version.dart';

class PatchPackInfo {
  PatchPackInfo._({
    required this.name,
    this.description,
    required this.authors,
    this.url,
    this.modpackName,
    this.versionRange,
    required this.delete,
    required this.rename,
  });

  final String name;
  final String? description;
  final List<String> authors;
  final String? url;
  final String? modpackName;
  final String? versionRange;
  final List<String> delete;
  final List<PatchRename> rename;

  factory PatchPackInfo.fromJson(Object? value) {
    final json = _object(value, 'patchpackinfo.json');
    if (json['formatVersion'] is! int || json['formatVersion'] != 1) {
      throw const FormatException('仅支持 formatVersion 为 1 的补丁包');
    }
    final name = _string(json, 'name');
    if (name == null) throw const FormatException('补丁包缺少名称');
    final modpack = json['modpack'] == null
        ? <String, dynamic>{}
        : _object(json['modpack'], 'modpack');
    final diff = json['diff'] == null
        ? <String, dynamic>{}
        : _object(json['diff'], 'diff');
    final renames = diff['rename'] ?? [];
    if (renames is! List) throw const FormatException('diff.rename 必须是数组');
    return PatchPackInfo._(
      name: name,
      description: _string(json, 'description'),
      authors: List.unmodifiable(_strings(json['authors'], 'authors')),
      url: _string(json, 'url'),
      modpackName: _string(modpack, 'name'),
      versionRange:
          _string(modpack, 'versionRange') ?? _string(modpack, 'VersionRange'),
      delete: List.unmodifiable(_strings(diff['delete'], 'diff.delete')),
      rename: List.unmodifiable(
        renames.map((value) {
          final rename = _object(value, 'diff.rename');
          final from = _string(rename, 'from');
          final to = _string(rename, 'to');
          if (from == null || to == null) {
            throw const FormatException('重命名操作缺少 from 或 to');
          }
          return PatchRename(from, to);
        }),
      ),
    );
  }

  List<String> compatibilityMessages(InstalledModpack? installed) {
    final messages = <String>[];
    if (modpackName != null) {
      if (installed?.name == null) {
        messages.add('无法获取当前实例的整合包名称，已跳过名称检查。');
      } else if (_normalizeName(modpackName!) !=
          _normalizeName(installed!.name!)) {
        messages.add('整合包名称不匹配：当前为“${installed.name}”，补丁适用于“$modpackName”。');
      }
    }
    if (installed?.version == null) {
      messages.add('无法获取当前实例的整合包版本，已跳过版本检查。');
    } else if (versionRange != null) {
      try {
        if (!MavenVersionRange(versionRange!).contains(installed!.version!)) {
          messages.add(
            '当前整合包版本 ${installed.version} 不在补丁适用范围 $versionRange 内。',
          );
        }
      } on FormatException {
        messages.add('无法解析补丁声明的版本范围“$versionRange”，请自行确认兼容性。');
      }
    }
    return messages;
  }
}

class PatchRename {
  const PatchRename(this.from, this.to);
  final String from;
  final String to;
}

class InstalledModpack {
  const InstalledModpack({this.name, this.version});
  final String? name;
  final String? version;

  factory InstalledModpack.fromManifest(
    Map<String, dynamic> manifest, {
    required bool modrinth,
  }) {
    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;
    return InstalledModpack(
      name: text(manifest['name']),
      version: text(manifest[modrinth ? 'versionId' : 'version']),
    );
  }
}

String _normalizeName(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

Map<String, dynamic> _object(Object? value, String field) {
  if (value is! Map<String, dynamic>) throw FormatException('$field 必须是对象');
  return value;
}

String? _string(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is! String) throw FormatException('$field 必须是字符串');
  return value.trim().isEmpty ? null : value.trim();
}

List<String> _strings(Object? value, String field) {
  if (value == null) return [];
  if (value is! List || value.any((v) => v is! String || v.trim().isEmpty)) {
    throw FormatException('$field 必须是非空字符串数组');
  }
  return value.cast<String>();
}
