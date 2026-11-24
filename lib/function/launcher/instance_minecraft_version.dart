import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

Future<String?> readInstanceMinecraftVersion(String instancePath) async {
  final name = p.basename(instancePath);
  // 实例 JSON 的文件名可以自定义, Minecraft 版本取自文件内容.
  for (final (fileName, keys) in [
    ('$name.json', ['inheritsFrom', 'id']),
    ('fml-mmc-profile.json', ['id']),
    ('fml-modpack.json', ['minecraft']),
  ]) {
    try {
      final data = jsonDecode(
        await File(p.join(instancePath, fileName)).readAsString(),
      );
      if (data is! Map) continue;
      for (final key in keys) {
        final value = data[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    } on FileSystemException {
      continue;
    } on FormatException {
      continue;
    }
  }
  return null;
}
