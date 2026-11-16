import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'app_config.dart';
import 'app_location.dart';

class ExportCancelled implements Exception {
  @override
  String toString() => '已取消导出';
}

class ExportCancellation {
  bool cancelled = false;
  void cancel() => cancelled = true;
  void check() {
    if (cancelled) throw ExportCancelled();
  }
}

class ExportProgress {
  const ExportProgress(this.stage, this.completed, this.total);
  final String stage;
  final int completed;
  final int total;
  double? get fraction =>
      total == 0 ? null : (completed / total).clamp(0.0, 1.0);
}

class _ExportEntry {
  const _ExportEntry(
    this.source,
    this.relative,
    this.type,
    this.size,
    this.mode,
  );
  final String source;
  final String relative;
  final FileSystemEntityType type;
  final int size;
  final int mode;
}

/// 只复制程序清单和配置快照, 从不读取或改动游戏目录内容.
class PortableExportService {
  PortableExportService(this.config, {AppLocation? location})
    : location = location ?? config.location ?? AppLocation.detect();
  final AppConfig config;
  final AppLocation location;
  static const manifestName = 'fml-runtime-files.json';
  bool _running = false;

  Future<String> export(
    String parent, {
    ExportCancellation? cancellation,
    void Function(ExportProgress)? onProgress,
  }) async {
    if (!config.canExportPortable) throw StateError('便携模式不能再次导出');
    if (_running) throw StateError('正在导出, 请等待完成');
    _running = true;
    final token = cancellation ?? ExportCancellation();
    Directory? staging;
    try {
      token.check();
      onProgress?.call(const ExportProgress('检查导出位置', 0, 0));
      final parentPath = await Directory(parent).resolveSymbolicLinks();
      final target = p.join(parentPath, 'FML-Portable');
      if (await FileSystemEntity.type(target, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw FileSystemException('FML-Portable 已存在, 请选择其他位置', target);
      }
      final data = await config.snapshot();
      final programRoot =
          location.platform == 'macos' && location.programPath.endsWith('.app')
          ? location.programPath
          : location.root;
      final sourceRoot = await Directory(programRoot).resolveSymbolicLinks();
      if (_inside(parentPath, sourceRoot)) {
        throw ArgumentError('导出位置不能位于源程序目录中');
      }
      for (final name in (data['PathList'] as List? ?? const [])) {
        final root = data['Path_$name'] as String?;
        if (root == null || root.isEmpty) continue;
        // 仅解析登记路径及其父级, 不枚举游戏文件.
        if (_inside(parentPath, p.normalize(p.absolute(root)))) {
          throw ArgumentError('导出位置不能位于游戏目录中: $name');
        }
        String resolved;
        try {
          resolved = await _resolveExistingAncestor(root)
              .timeout(const Duration(seconds: 5));
        } on FileSystemException {
          continue;
        } on TimeoutException {
          continue;
        }
        if (_inside(parentPath, resolved)) {
          throw ArgumentError('导出位置不能位于游戏目录中: $name');
        }
      }
      token.check();
      final entries = await _entries();
      if (entries.isEmpty) throw StateError('未找到程序运行文件');
      final total = entries.fold<int>(0, (sum, item) => sum + item.size);
      staging = await Directory(parentPath).createTemp('.fml-export-');
      var copied = 0;
      final links = <_ExportEntry>[];
      final directories = <_ExportEntry>[];
      for (final entry in entries) {
        token.check();
        final destination = p.join(staging.path, entry.relative);
        if (entry.type == FileSystemEntityType.directory) {
          await Directory(destination).create(recursive: true);
          directories.add(entry);
        } else if (entry.type == FileSystemEntityType.link) {
          links.add(entry);
        } else {
          await File(destination).parent.create(recursive: true);
          final sink = File(destination).openWrite();
          try {
            await sink.addStream(
              File(entry.source).openRead().map((chunk) {
                token.check();
                copied += chunk.length;
                onProgress?.call(
                  ExportProgress('复制程序: ${entry.relative}', copied, total),
                );
                return chunk;
              }),
            );
            await sink.flush();
          } finally {
            await sink.close();
          }
          await _permissions(destination, entry.mode);
          final sourceHash = await sha256
              .bind(File(entry.source).openRead())
              .first;
          token.check();
          final targetHash = await sha256
              .bind(File(destination).openRead())
              .first;
          if (sourceHash != targetHash ||
              await File(destination).length() != entry.size) {
            throw FileSystemException('程序文件校验失败', entry.relative);
          }
        }
      }
      for (final entry in links) {
        token.check();
        final destination = p.join(staging.path, entry.relative);
        await File(destination).parent.create(recursive: true);
        final original = await Link(entry.source).target();
        final resolved = await Link(entry.source).resolveSymbolicLinks();
        // 所有程序链接必须指向本次复制的内容.
        final candidates = entries.where(
          (other) => p.equals(p.normalize(other.source), resolved),
        );
        if (candidates.isEmpty) {
          throw FileSystemException('程序链接指向运行清单之外', entry.source);
        }
        final mapped = p.join(staging.path, candidates.first.relative);
        await Link(destination).create(
          p.isAbsolute(original)
              ? p.relative(mapped, from: p.dirname(destination))
              : original,
        );
      }
      for (final entry in directories.reversed) {
        await _permissions(p.join(staging.path, entry.relative), entry.mode);
      }
      token.check();
      onProgress?.call(ExportProgress('保存配置', copied, total));
      final settings = File(p.join(staging.path, 'FML-data', 'settings.json'));
      await settings.parent.create();
      await settings.writeAsString(jsonEncode(data), flush: true);
      if (jsonEncode(jsonDecode(await settings.readAsString())) !=
          jsonEncode(data)) {
        throw StateError('导出配置校验失败');
      }
      token.check();
      if (await FileSystemEntity.type(target, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw FileSystemException('目标目录已被占用', target);
      }
      await staging.rename(target);
      staging = null;
      onProgress?.call(ExportProgress('导出完成', total, total));
      return target;
    } finally {
      try {
        if (staging != null && await staging.exists()) {
          await staging.delete(recursive: true);
        }
      } finally {
        _running = false;
      }
    }
  }

  static bool _inside(String child, String parent) =>
      p.equals(child, parent) || p.isWithin(parent, child);

  static Future<String> _resolveExistingAncestor(String value) async {
    var current = p.normalize(p.absolute(value));
    final missing = <String>[];
    while (true) {
      try {
        final resolved = await Directory(current).resolveSymbolicLinks();
        return p.normalize(p.joinAll([resolved, ...missing.reversed]));
      } on FileSystemException catch (error) {
        final code = error.osError?.errorCode;
        if (!(code == 2 ||
            Platform.isWindows && code == 3 ||
            !Platform.isWindows && code == 20)) {
          rethrow;
        }
        final parent = p.dirname(current);
        if (parent == current) return p.normalize(p.absolute(value));
        missing.add(p.basename(current));
        current = parent;
      }
    }
  }

  Future<List<_ExportEntry>> _entries() async {
    final result = <_ExportEntry>[];
    Future<void> add(String source, String relative) async {
      final type = await FileSystemEntity.type(source, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        throw FileSystemException('程序文件缺失', source);
      }
      final stat = await FileStat.stat(source);
      result.add(
        _ExportEntry(
          source,
          relative,
          type,
          type == FileSystemEntityType.file ? stat.size : 0,
          stat.mode,
        ),
      );
    }

    if (location.appImage) {
      await add(location.programPath, p.basename(location.programPath));
    } else if (location.platform == 'macos' &&
        location.programPath.endsWith('.app')) {
      final bundle = Directory(
        await Directory(location.programPath).resolveSymbolicLinks(),
      );
      await add(bundle.path, p.basename(bundle.path));
      await for (final entity in bundle.list(
        recursive: true,
        followLinks: false,
      )) {
        await add(
          entity.path,
          p.join(
            p.basename(bundle.path),
            p.relative(entity.path, from: bundle.path),
          ),
        );
      }
    } else {
      final manifest = File(p.join(location.root, manifestName));
      if (!await manifest.exists()) throw StateError('缺少程序运行文件清单, 请使用正式构建导出');
      final paths = (jsonDecode(await manifest.readAsString()) as List)
          .cast<String>();
      if (!paths.contains(p.basename(location.programPath))) {
        throw StateError('运行清单未包含主程序');
      }
      final root = await Directory(location.root).resolveSymbolicLinks();
      for (final relative in {...paths, manifestName}) {
        if (p.isAbsolute(relative) ||
            p.split(relative).contains('..') ||
            p.split(relative).first == 'FML-data') {
          throw FormatException('无效运行文件路径: $relative');
        }
        final source = p.join(root, relative);
        final actualParent = await Directory(p.dirname(source))
            .resolveSymbolicLinks();
        if (!_inside(actualParent, root)) {
          throw FormatException('运行文件位于程序目录之外: $relative');
        }
        await add(source, relative);
      }
    }
    result.sort((a, b) => a.relative.compareTo(b.relative));
    return result;
  }

  static Future<void> _permissions(String path, int mode) async {
    if (Platform.isWindows) return;
    final result = await Process.run('chmod', [
      (mode & 0x1ff).toRadixString(8),
      path,
    ]);
    if (result.exitCode != 0) throw FileSystemException('无法保留程序权限', path);
  }
}
