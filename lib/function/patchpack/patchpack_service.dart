import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'patchpack_info.dart';

const _manifestName = 'patchpackinfo.json';
const _maxArchiveSize = 512 * 1024 * 1024;
const _maxExpandedSize = 1024 * 1024 * 1024;
const _maxManifestSize = 1024 * 1024;

class PatchPack {
  PatchPack._(this.info, this.stagingPath, this.entries);
  final PatchPackInfo info;
  final String stagingPath;
  final List<PatchEntry> entries;
  int get fileCount => entries.where((e) => !e.isDirectory).length;

  static Future<PatchPack> open(String path) => Isolate.run(() => _open(path));

  static PatchPack _open(String path) {
    final source = File(path);
    if (source.lengthSync() > _maxArchiveSize) {
      throw const FormatException('补丁 ZIP 超过 512 MiB');
    }
    final input = InputFileStream(path);
    Directory? staging;
    try {
      final decoder = ZipDecoder();
      final archive = decoder.decodeStream(input);
      if (decoder.directory.fileHeaders.length > 20000) {
        throw const FormatException('补丁包文件数量超过限制');
      }
      final names = <String>{};
      for (final header in decoder.directory.fileHeaders) {
        final name = _relativePath(header.filename);
        if (!names.add(name.toLowerCase())) {
          throw FormatException('补丁包包含重复路径: $name');
        }
      }
      var size = 0;
      for (final entry in archive) {
        _relativePath(entry.name);
        final type = entry.mode & 0xf000;
        if (entry.isSymbolicLink ||
            (type != 0 && type != 0x8000 && type != 0x4000)) {
          throw FormatException('补丁包不允许包含符号链接或特殊文件: ${entry.name}');
        }
        size += entry.size;
        if (entry.size < 0 ||
            size > _maxExpandedSize ||
            entry.size > _maxArchiveSize) {
          throw const FormatException('补丁包解压大小超过限制');
        }
      }
      final manifest = archive.find(_manifestName);
      if (manifest == null || !manifest.isFile) {
        throw const FormatException('ZIP 根目录缺少 patchpackinfo.json');
      }
      if (manifest.size > _maxManifestSize) {
        throw const FormatException('补丁信息文件过大');
      }
      final info = PatchPackInfo.fromJson(
        jsonDecode(utf8.decode(_checkedBytes(manifest))),
      );
      for (final path in info.delete) {
        _checkReserved(_relativePath(path));
      }
      for (final rename in info.rename) {
        _checkReserved(_relativePath(rename.from));
        _checkReserved(_relativePath(rename.to));
      }
      staging = Directory.systemTemp.createTempSync('fml-patchpack-');
      final entries = <PatchEntry>[];
      for (final entry in archive) {
        if (entry.name == _manifestName) continue;
        final name = _relativePath(entry.name);
        _checkReserved(name);
        final destination = p.joinAll([staging.path, ...name.split('/')]);
        if (entry.isDirectory) {
          Directory(destination).createSync(recursive: true);
        } else {
          final bytes = _checkedBytes(entry);
          File(destination).parent.createSync(recursive: true);
          File(destination).writeAsBytesSync(bytes);
        }
        entries.add(PatchEntry(name, entry.isDirectory));
      }
      return PatchPack._(info, staging.path, List.unmodifiable(entries));
    } catch (_) {
      staging?.deleteSync(recursive: true);
      rethrow;
    } finally {
      input.closeSync();
    }
  }

  Future<void> dispose() async {
    final directory = Directory(stagingPath);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<void> validateTarget(String instancePath) =>
      Isolate.run(() => _preflight(instancePath));

  Future<void> install(
    String instancePath, {
    void Function(double)? onProgress,
  }) async {
    // 在执行变更操作之前，立即再次验证完整的操作序列
    await validateTarget(instancePath);
    final root = await Directory(instancePath).resolveSymbolicLinks();
    final total = info.delete.length + info.rename.length + entries.length;
    var completed = 0;
    void progress() => onProgress?.call(total == 0 ? 1 : ++completed / total);
    for (final relative in info.delete) {
      final target = _safeTarget(root, relative);
      final type = FileSystemEntity.typeSync(target, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        _checkTree(target);
        await Directory(target).delete(recursive: true);
      } else if (type == FileSystemEntityType.file) {
        await File(target).delete();
      }
      progress();
    }
    for (final rename in info.rename) {
      final from = _safeTarget(root, rename.from);
      final to = _safeTarget(root, rename.to);
      final type = FileSystemEntity.typeSync(from, followLinks: false);
      if (from != to && type != FileSystemEntityType.notFound) {
        if (FileSystemEntity.typeSync(to, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw FileSystemException('重命名目标已存在', to);
        }
        await Directory(p.dirname(to)).create(recursive: true);
        if (type == FileSystemEntityType.directory) {
          _checkTree(from);
          await Directory(from).rename(to);
        } else {
          await File(from).rename(to);
        }
      }
      progress();
    }
    for (final entry in entries) {
      final destination = _safeTarget(root, entry.path);
      if (entry.isDirectory) {
        await Directory(destination).create(recursive: true);
      } else {
        await Directory(p.dirname(destination)).create(recursive: true);
        // 以原子方式替换单个文件
        final temporary = await Directory(p.dirname(destination))
            .createTemp('.fml-patch-');
        try {
          final file = await File(
            p.joinAll([stagingPath, ...entry.path.split('/')]),
          ).copy(p.join(temporary.path, 'content'));
          _safeTarget(root, entry.path);
          await file.rename(destination);
        } finally {
          await temporary.delete(recursive: true);
        }
      }
      progress();
    }
    onProgress?.call(1);
  }

  void _preflight(String instancePath) {
    if (instancePath.isEmpty ||
        FileSystemEntity.typeSync(instancePath, followLinks: false) !=
            FileSystemEntityType.directory) {
      throw const FileSystemException('目标实例文件夹不存在或是符号链接');
    }
    final root = Directory(instancePath).resolveSymbolicLinksSync();
    final instanceName = p.basename(instancePath).toLowerCase();
    final paths = [
      ...info.delete,
      for (final rename in info.rename) ...[rename.from, rename.to],
      ...entries.map((e) => e.path),
    ];
    for (final path in paths) {
      final name = _relativePath(path);
      _checkReserved(name);
      if (name.toLowerCase() == '$instanceName.json' ||
          name.toLowerCase() == '$instanceName.jar') {
        throw FormatException('补丁不能修改游戏启动文件: $path');
      }
      _safeTarget(root, name);
    }
    for (final path in [...info.delete, ...info.rename.map((r) => r.from)]) {
      _checkTree(_safeTarget(root, path));
    }
    final tree = _PlannedTree(root);
    for (final path in info.delete) {
      tree.remove(_relativePath(path));
    }
    for (final rename in info.rename) {
      tree.rename(_relativePath(rename.from), _relativePath(rename.to));
    }
    for (final entry in entries) {
      tree.write(entry.path, entry.isDirectory);
    }
  }
}

class PatchEntry {
  const PatchEntry(this.path, this.isDirectory);
  final String path;
  final bool isDirectory;
}

List<int> _checkedBytes(ArchiveFile file) {
  final bytes = file.content;
  if (bytes.length != file.size ||
      (file.crc32 != null && getCrc32(bytes) != file.crc32)) {
    throw FormatException('补丁文件校验失败: ${file.name}');
  }
  return bytes;
}

String _relativePath(String value) {
  final path = value.replaceAll('\\', '/').replaceFirst(RegExp(r'/+$'), '');
  final parts = path.split('/');
  if (path.isEmpty ||
      path.startsWith('/') ||
      parts.any(
        (v) =>
            v.isEmpty ||
            v == '.' ||
            v == '..' ||
            v.endsWith('.') ||
            v.endsWith(' ') ||
            RegExp(r'[\x00-\x1f\x7f:<>"|?*]').hasMatch(v) ||
            RegExp(
              r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
              caseSensitive: false,
            ).hasMatch(v),
      )) {
    throw FormatException('补丁包含不安全的相对路径: $value');
  }
  return path;
}

void _checkReserved(String relative) {
  final first = relative.split('/').first.toLowerCase();
  if (const {
    'assets',
    'libraries',
    'natives',
    'versions',
    '.git',
    'fabric.json',
    'neoforge.json',
    'forge.json',
    'forge-installer.jar',
    'forge-modpack.zip',
    'fml-modpack.json',
    'mrpack',
    'curseforge',
    _manifestName,
  }.contains(first)) {
    throw FormatException('补丁不能修改启动器管理的文件或目录: $relative');
  }
}

String _safeTarget(String root, String relative) {
  var current = root;
  for (final part in ['', ..._relativePath(relative).split('/')]) {
    if (part.isNotEmpty) current = p.join(current, part);
    final type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException('补丁路径包含符号链接或特殊文件', current);
    }
  }
  return current;
}

void _checkTree(String target) {
  if (FileSystemEntity.typeSync(target, followLinks: false) !=
      FileSystemEntityType.directory) {
    return;
  }
  for (final entity in Directory(
    target,
  ).listSync(recursive: true, followLinks: false)) {
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException('操作目录内包含符号链接或特殊文件', entity.path);
    }
  }
}

class _PlannedTree {
  _PlannedTree(this.root);
  final String root;
  final List<_TreeChange> changes = [];
  String key(String path) => Platform.isLinux ? path : path.toLowerCase();
  bool within(String path, String parent) =>
      path == parent || path.startsWith('$parent/');

  FileSystemEntityType type(String path, [int? before]) {
    final normalized = key(path);
    for (var i = (before ?? changes.length) - 1; i >= 0; i--) {
      final change = changes[i];
      if (!within(normalized, key(change.path))) continue;
      if (change.from != null) {
        return type('${change.from}${path.substring(change.path.length)}', i);
      }
      if (normalized == key(change.path)) return change.type!;
      return FileSystemEntityType.notFound;
    }
    return FileSystemEntity.typeSync(
      p.joinAll([root, ...path.split('/')]),
      followLinks: false,
    );
  }

  void remove(String path) =>
      changes.add(_TreeChange(path, type: FileSystemEntityType.notFound));

  void parents(String path) {
    final parts = path.split('/');
    for (var i = 1; i < parts.length; i++) {
      final parent = parts.take(i).join('/');
      final existing = type(parent);
      if (existing == FileSystemEntityType.notFound) {
        changes.add(_TreeChange(parent, type: FileSystemEntityType.directory));
      } else if (existing != FileSystemEntityType.directory) {
        throw FileSystemException('目标父路径不是目录', parent);
      }
    }
  }

  void rename(String from, String to) {
    if (from == to) return;
    if (within(key(to), key(from)) || within(key(from), key(to))) {
      throw FormatException('重命名路径不能互相包含: $from → $to');
    }
    if (type(from) == FileSystemEntityType.notFound) return;
    if (type(to) != FileSystemEntityType.notFound) {
      throw FileSystemException('重命名目标已存在', to);
    }
    parents(to);
    changes.add(_TreeChange(to, from: from));
    remove(from);
  }

  void write(String path, bool directory) {
    parents(path);
    final existing = type(path);
    final desired = directory
        ? FileSystemEntityType.directory
        : FileSystemEntityType.file;
    if (existing != FileSystemEntityType.notFound && existing != desired) {
      throw FileSystemException('补丁文件与现有目录或文件冲突', path);
    }
    // Existing directories must keep their children in the simulated tree.
    if (existing == FileSystemEntityType.notFound || !directory) {
      changes.add(_TreeChange(path, type: desired));
    }
  }
}

class _TreeChange {
  const _TreeChange(this.path, {this.from, this.type});
  final String path;
  final String? from;
  final FileSystemEntityType? type;
}

Future<InstalledModpack?> readInstalledModpack(
  String instancePath,
) => Isolate.run(() {
  for (final candidate in [
    ('fml-modpack.json', false),
    ('mrpack/modrinth.index.json', true),
    ('curseforge/manifest.json', false),
    ('modrinth.index.json', true),
    ('manifest.json', false),
  ]) {
    final file = File(p.joinAll([instancePath, ...candidate.$1.split('/')]));
    try {
      if (!file.existsSync() || file.lengthSync() > _maxManifestSize) continue;
      final data = jsonDecode(file.readAsStringSync());
      if (data is Map<String, dynamic>) {
        return InstalledModpack.fromManifest(data, modrinth: candidate.$2);
      }
    } on FileSystemException {
      continue;
    } on FormatException {
      continue;
    }
  }
  final file = File(p.join(instancePath, 'forge-modpack.zip'));
  if (!file.existsSync() || file.lengthSync() > _maxArchiveSize) return null;
  InputFileStream? input;
  try {
    input = InputFileStream(file.path);
    final archive = ZipDecoder().decodeStream(input);
    for (final name in ['modrinth.index.json', 'manifest.json']) {
      final entry = archive.find(name);
      if (entry == null || !entry.isFile || entry.size > _maxManifestSize) {
        continue;
      }
      final data = jsonDecode(utf8.decode(_checkedBytes(entry)));
      if (data is Map<String, dynamic>) {
        return InstalledModpack.fromManifest(
          data,
          modrinth: name == 'modrinth.index.json',
        );
      }
    }
  } catch (_) {
    return null;
  } finally {
    input?.closeSync();
  }
  return null;
});
