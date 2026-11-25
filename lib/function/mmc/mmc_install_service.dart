import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:system_info2/system_info2.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../forge/forge_metadata.dart';
import '../forge/forge_service.dart';
import '../java/java_launch_check.dart';
import '../java/java_utils.dart';
import 'instance_runtime_installer.dart';
import 'mmc_pack.dart';
import 'mmc_runtime_installer.dart'
    show MmcCustomRuntimeInstaller, installMmcRuntime;

typedef MmcDefaultRuntimeInstaller = Future<void> Function({
  required String gamePath,
  required String name,
  required String minecraft,
  required String loader,
  String? loaderVersion,
  String? instancePath,
  Map<String, String> runtimeComponents,
  required void Function(String, double?) onProgress,
  required void Function() checkCancelled,
  required String javaExecutable,
});

class MmcInstallCancelled implements Exception {
  const MmcInstallCancelled();

  @override
  String toString() => '已取消导入';
}

class MmcInstallCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
  void check() {
    if (_cancelled) throw const MmcInstallCancelled();
  }
}

enum MmcFileConflictChoice { existing, incoming }

class MmcConflictFile {
  const MmcConflictFile({
    required this.relativePath,
    required this.size,
    required this.preview,
  });

  final String relativePath;
  final int size;
  final Uint8List preview;
}

class MmcFileConflict {
  const MmcFileConflict({
    required this.existing,
    required this.incoming,
    required this.identical,
  });

  final MmcConflictFile existing;
  final MmcConflictFile incoming;
  final bool identical;
}

/// 返回 null 会取消导入, 并清理本次安装的暂存文件.
typedef MmcFileConflictResolver = Future<MmcFileConflictChoice?> Function(
  MmcFileConflict conflict,
);

class MmcInstallService {
  MmcInstallService({
    required this.config,
    this.runtimeInstaller = installInstanceRuntime,
    this.customRuntimeInstaller = installMmcRuntime,
    this.memoryMiB,
    this.javaArchitecture = _javaArchitecture,
  });

  final AppConfig config;
  final MmcDefaultRuntimeInstaller runtimeInstaller;
  final MmcCustomRuntimeInstaller customRuntimeInstaller;
  final int? memoryMiB;
  final Future<String?> Function(String) javaArchitecture;

  static Future<String?> _javaArchitecture(String executable) async =>
      await JavaUtils.probeJavaArchitecture(executable);
  static const _markerName = '.fml-mmc-install.json';

  Future<void> install({
    required MmcPack pack,
    required String pathName,
    required String gamePath,
    required String name,
    required void Function(String, double?) onProgress,
    MmcInstallCancellation? cancellation,
    MmcFileConflictResolver? onFileConflict,
  }) async {
    final cancel = cancellation ?? MmcInstallCancellation();
    cancel.check();
    if (instanceNameError(name) case final String error) {
      throw FormatException(error);
    }
    final initial = await config.snapshot();
    _validateRegistration(initial, pathName, gamePath, name);
    if (!await Directory(gamePath).exists()) {
      throw StateError('目标游戏目录不存在, 请重新选择');
    }
    final root = await Directory(gamePath).resolveSymbolicLinks();
    final versions = Directory(p.join(root, 'versions'));
    final versionsType = await FileSystemEntity.type(
      versions.path,
      followLinks: false,
    );
    if (versionsType != FileSystemEntityType.notFound &&
        versionsType != FileSystemEntityType.directory) {
      throw StateError('versions 必须是普通目录, 不能是符号链接');
    }
    await versions.create();
    final memory = memoryMiB ?? _defaultMemory();
    final destination = Directory(p.join(versions.path, name));
    final lockKey = sha256.convert(utf8.encode(name.toLowerCase()));
    final lock = File(p.join(versions.path, '.fml-mmc-$lockKey.lock'));
    try {
      await lock.create(exclusive: true);
    } on FileSystemException {
      throw StateError('无法锁定此版本, 可能已有同名导入任务: ${lock.path}');
    }

    Directory? staging;
    final token = const Uuid().v4();
    var published = false;
    var committed = false;
    var keepPublished = false;
    Map<String, Object>? beforeRegistration;
    final configKey = 'Config_${pathName}_$name';
    final gameKey = 'Game_$pathName';
    final installedConfig = [
      '$memory',
      '0',
      '854',
      '480',
      pack.info.loader.configName,
      '',
    ];
    try {
      _ensureDestinationAbsent(versions, name);
      cancel.check();
      onProgress('正在检查导入文件', null);
      final entries = await _sourceEntries(pack, name, cancel);
      onProgress('正在检查导入文件', 1);
      staging = await versions.createTemp('.fml-mmc-');
      await File(p.join(staging.path, _markerName)).writeAsString(token);

      await _copyGameFiles(
        entries,
        staging.path,
        name,
        cancel,
        (value) => onProgress('正在复制整合包文件', value),
        onFileConflict,
      );
      cancel.check();
      final javaExecutable = await configuredJavaExecutable(config);
      final components = pack.info.components;
      if (components != null) {
        final arch = await javaArchitecture(javaExecutable);
        cancel.check();
        if (arch == null || arch.isEmpty) {
          throw StateError('无法识别 Java 架构, 请先在设置中选择有效的 Java');
        }
        final profile = await components.resolve(
          arch: arch,
          loadJson: ForgeInstaller.jsonUrl,
          checkCancelled: cancel.check,
        );
        await customRuntimeInstaller(
          gamePath: root,
          instancePath: staging.path,
          name: name,
          profile: profile,
          runtimePath: pack.runtimePath,
          javaExecutable: javaExecutable,
          onProgress: onProgress,
          checkCancelled: cancel.check,
        );
      } else {
        await runtimeInstaller(
          gamePath: root,
          instancePath: staging.path,
          name: name,
          minecraft: pack.info.minecraft,
          loader: pack.info.loader.configName,
          loaderVersion: pack.info.loaderVersion,
          runtimeComponents: pack.info.runtimeComponents,
          javaExecutable: javaExecutable,
          onProgress: onProgress,
          checkCancelled: cancel.check,
        );
      }
      cancel.check();
      await _validateRuntime(staging.path, name, pack.info);
      await File(p.join(staging.path, 'fml-modpack.json')).writeAsString(
        jsonEncode({
          'name': pack.info.name,
          'source': 'mmc',
          'minecraft': pack.info.minecraft,
          'loader': pack.info.loader.configName,
          if (pack.info.loaderVersion != null)
            'loaderVersion': pack.info.loaderVersion,
        }),
      );

      onProgress('正在保存游戏配置', null);
      // 在配置串行锁内再次检查名称与目标, 再发布完整的实例目录.
      await config.edit((data) {
        cancel.check();
        _validateRegistration(data, pathName, gamePath, name);
        if (Directory(gamePath).resolveSymbolicLinksSync() != root ||
            FileSystemEntity.typeSync(versions.path, followLinks: false) !=
                FileSystemEntityType.directory) {
          throw StateError('安装期间游戏目录发生变化');
        }
        _ensureDestinationAbsent(versions, name);
        staging!.renameSync(destination.path);
        published = true;
        beforeRegistration = Map.of(data);
        data[configKey] = installedConfig;
        data[gameKey] = [
          ...List<String>.from((data[gameKey] as List?) ?? const []),
          name,
        ];
        data['SelectedPath'] = pathName;
        data['SelectedGame'] = name;
      });
      committed = true;
      onProgress('正在保存游戏配置', 1);
    } catch (error) {
      if (published && !committed && beforeRegistration != null) {
        try {
          // 系统配置可能分键写入, 失败时只撤销本次注册的字段.
          await config.edit((data) {
            if (jsonEncode(data[configKey]) == jsonEncode(installedConfig)) {
              data.remove(configKey);
            }
            final games = List<String>.from((data[gameKey] as List?) ?? []);
            games.remove(name);
            if (beforeRegistration!.containsKey(gameKey) || games.isNotEmpty) {
              data[gameKey] = games;
            } else {
              data.remove(gameKey);
            }
            for (final entry in {
              'SelectedPath': pathName,
              'SelectedGame': name,
            }.entries) {
              final key = entry.key;
              if (data[key] == entry.value) {
                if (beforeRegistration!.containsKey(key)) {
                  data[key] = beforeRegistration![key]!;
                } else {
                  data.remove(key);
                }
              }
            }
          });
        } catch (rollbackError) {
          keepPublished = true;
          throw StateError(
            '保存配置失败, 且无法撤销配置: $error; $rollbackError. '
            '已保留完整游戏文件: ${destination.path}',
          );
        }
      }
      rethrow;
    } finally {
      try {
        if (committed) {
          try {
            await File(p.join(destination.path, _markerName)).delete();
          } on FileSystemException {
            // 安装已经完成, 清理标记失败不改变结果.
          }
        } else if (!keepPublished && staging != null) {
          final owned = published ? destination : staging;
          final marker = File(p.join(owned.path, _markerName));
          if (await FileSystemEntity.type(owned.path, followLinks: false) ==
                  FileSystemEntityType.directory &&
              ((!published && !await marker.exists()) ||
                  await marker.readAsString() == token)) {
            await owned.delete(recursive: true);
          }
        }
      } finally {
        try {
          if (await lock.exists()) await lock.delete();
        } on FileSystemException {
          // 清理锁文件失败不应把已经提交的安装报告为失败.
          if (!committed) rethrow;
        }
      }
    }
  }

  static int _defaultMemory() {
    var bytes = SysInfo.getTotalPhysicalMemory();
    if (bytes > 1024 * 1024 * 1024 * 1024 && bytes % 16384 == 0) {
      bytes ~/= 16384;
    }
    return (bytes ~/ (1024 * 1024 * 2)).clamp(1024, 8192);
  }

  static void _validateRegistration(
    Map<String, Object> data,
    String pathName,
    String gamePath,
    String name,
  ) {
    if (pathName.isEmpty ||
        gamePath.isEmpty ||
        !(data['PathList'] as List? ?? []).contains(pathName) ||
        data['Path_$pathName'] != gamePath) {
      throw StateError('目标游戏目录的配置已改变, 请重新选择');
    }
    if ((data['Game_$pathName'] as List? ?? []).any(
          (value) => value.toString().toLowerCase() == name.toLowerCase(),
        ) ||
        data.containsKey('Config_${pathName}_$name')) {
      throw StateError('已存在同名版本, 请更换版本名称');
    }
  }

  static void _ensureDestinationAbsent(Directory versions, String name) {
    if (FileSystemEntity.typeSync(
              p.join(versions.path, name),
              followLinks: false,
            ) !=
            FileSystemEntityType.notFound ||
        versions
            .listSync(followLinks: false)
            .any(
              (entry) =>
                  p.basename(entry.path).toLowerCase() == name.toLowerCase(),
            )) {
      throw StateError('已存在同名版本文件或目录, 请更换版本名称');
    }
  }

  static Map<String, bool> _reservedPaths(String name) => {
    '$name.json': false,
    '$name.jar': false,
    'Forge.json': false,
    'NeoForge.json': false,
    'fabric.json': false,
    'fml-modpack.json': false,
    'fml-mmc-profile.json': false,
    _markerName: false,
    'natives': true,
    'versions': true,
    'libraries': true,
    'assets': true,
    '.fml-mmc-runtime': true,
  };

  static Future<List<_GameEntry>> _sourceEntries(
    MmcPack pack,
    String name,
    MmcInstallCancellation cancel,
  ) async {
    final source = pack.stagingPath;
    if (await FileSystemEntity.type(source, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('整合包临时文件已失效, 请重新选择 ZIP');
    }
    final result = <_GameEntry>[];
    final reserved = _reservedPaths(name).keys
        .map((path) => path.toLowerCase())
        .toSet();
    void validate(String relative) {
      safeChild(source, relative);
      if (reserved.contains(
        relative.replaceAll('\\', '/').split('/').first.toLowerCase(),
      )) {
        throw FormatException('整合包文件与启动配置冲突: $relative');
      }
    }

    if (pack.gameFiles.isNotEmpty || pack.gameDirectories.isNotEmpty) {
      for (final relative in pack.gameDirectories) {
        cancel.check();
        validate(relative);
        result.add(_GameEntry(relative));
      }
      for (final entry in pack.gameFiles.entries) {
        cancel.check();
        validate(entry.key);
        final blob = safeChild(source, entry.value);
        var parent = p.dirname(blob);
        while (parent != source && p.isWithin(source, parent)) {
          if (await FileSystemEntity.type(parent, followLinks: false) !=
              FileSystemEntityType.directory) {
            throw FormatException(
              '整合包临时文件包含无效目录: ${entry.key} / ${entry.value}',
            );
          }
          parent = p.dirname(parent);
        }
        if (await FileSystemEntity.type(blob, followLinks: false) !=
            FileSystemEntityType.file) {
          throw FormatException('整合包临时文件已失效: ${entry.key} / ${entry.value}');
        }
        result.add(_GameEntry(entry.key, sourcePath: blob));
      }
    } else {
      await for (final entity in Directory(
        source,
      ).list(recursive: true, followLinks: false)) {
        cancel.check();
        if (entity is! File && entity is! Directory) {
          throw FormatException('整合包包含符号链接或特殊文件: ${entity.path}');
        }
        final relative = p.relative(entity.path, from: source);
        validate(relative);
        result.add(
          _GameEntry(relative, sourcePath: entity is File ? entity.path : null),
        );
      }
    }
    return result;
  }

  static Future<void> _copyGameFiles(
    List<_GameEntry> entries,
    String target,
    String name,
    MmcInstallCancellation cancel,
    void Function(double?) onProgress,
    MmcFileConflictResolver? onFileConflict,
  ) async {
    onProgress(0);
    final root = _TargetEntry(target, '', directory: true);
    final placeholders = <FileSystemEntity>[];
    // 先用真实目标文件系统占位, 在任何运行时请求前识别大小写和 Unicode 等价冲突.
    for (final reserved in _reservedPaths(name).entries) {
      cancel.check();
      final output = safeChild(target, reserved.key);
      if (reserved.key != _markerName) {
        _TargetEntry? equivalent;
        if (await FileSystemEntity.type(output, followLinks: false) !=
            FileSystemEntityType.notFound) {
          for (final sibling in root.children.values) {
            if (await FileSystemEntity.identical(output, sibling.output)) {
              equivalent = sibling;
              break;
            }
          }
        }
        if (equivalent != null && equivalent.directory == reserved.value) {
          root.children[reserved.key] = equivalent;
          continue;
        }
        final FileSystemEntity entity;
        if (reserved.value) {
          entity = await Directory(output).create();
        } else {
          entity = await File(output).create(exclusive: true);
        }
        placeholders.add(entity);
      }
      root.children[reserved.key] = _TargetEntry(
        output,
        reserved.key,
        directory: reserved.value,
        reserved: true,
      );
    }

    var completed = 0;
    for (final entry in entries) {
      cancel.check();
      final parts = entry.relative.replaceAll('\\', '/').split('/');
      var parent = root;
      for (var index = 0; index < parts.length; index++) {
        final segment = parts[index];
        if (segment.isEmpty || segment == '.') {
          throw FormatException('无效的整合包路径: ${entry.relative}');
        }
        final directory = index < parts.length - 1 || entry.sourcePath == null;
        final output = safeChild(parent.output, segment);
        var existing = parent.children[segment];
        if (existing == null &&
            await FileSystemEntity.type(output, followLinks: false) !=
                FileSystemEntityType.notFound) {
          // 只在文件系统报告已存在时比较同级节点, 避免逐文件全表扫描.
          for (final sibling in parent.children.values.toSet()) {
            if (await FileSystemEntity.identical(output, sibling.output)) {
              existing = sibling;
              break;
            }
          }
          if (existing == null) {
            throw FormatException('整合包路径与已有文件冲突: ${entry.relative} / $output');
          }
        }
        if (existing != null) {
          if (!existing.reserved && directory && existing.directory) {
            parent.children[segment] = existing;
            parent = existing;
            continue;
          }
          if (existing.reserved ||
              directory ||
              existing.directory ||
              existing.relative == entry.relative ||
              onFileConflict == null) {
            throw FormatException(
              '整合包路径冲突: ${existing.relative} / ${entry.relative}',
            );
          }
          final conflict = await _describeConflict(existing, entry, cancel);
          cancel.check();
          final choice = await onFileConflict(conflict);
          cancel.check();
          if (choice == null) throw const MmcInstallCancelled();
          if (choice == MmcFileConflictChoice.existing) {
            parent.children[segment] = existing;
            break;
          }
          // 先删除暂存副本, 随后用选中的文件名排他创建, 保留选中的大小写.
          await File(existing.output).delete();
          parent.children.removeWhere((_, child) => child == existing);
        }
        final created = _TargetEntry(
          output,
          entry.relative,
          directory: directory,
        );
        if (directory) {
          await Directory(output).create();
        } else {
          // 排他创建后再流式写入, 不覆盖目标文件系统中的等价叶节点.
          await File(output).create(exclusive: true);
          final sink = File(output).openWrite();
          try {
            await sink.addStream(
              File(entry.sourcePath!).openRead().map((chunk) {
                cancel.check();
                return chunk;
              }),
            );
            await sink.flush();
          } finally {
            await sink.close();
          }
        }
        parent.children[segment] = created;
        parent = created;
      }
      onProgress(++completed / entries.length);
    }
    for (final placeholder in placeholders.reversed) {
      cancel.check();
      await placeholder.delete();
    }
    onProgress(1);
  }

  static Future<MmcFileConflict> _describeConflict(
    _TargetEntry existing,
    _GameEntry incoming,
    MmcInstallCancellation cancel,
  ) async {
    cancel.check();
    final written = await File(existing.output).open();
    RandomAccessFile? source;
    try {
      source = await File(incoming.sourcePath!).open();
      final existingSize = await written.length();
      final incomingSize = await source.length();
      final existingPreview = await written.read(16 * 1024);
      final incomingPreview = await source.read(16 * 1024);
      var identical =
          existingSize == incomingSize &&
          _sameBytes(existingPreview, incomingPreview);
      var remaining = existingSize - existingPreview.length;
      while (identical && remaining > 0) {
        cancel.check();
        final count = remaining > 64 * 1024 ? 64 * 1024 : remaining;
        final left = await written.read(count);
        final right = await source.read(count);
        if (left.length != count || right.length != count) {
          throw const FileSystemException('读取待比较文件时文件大小发生变化');
        }
        identical = _sameBytes(left, right);
        remaining -= count;
      }
      return MmcFileConflict(
        existing: MmcConflictFile(
          relativePath: existing.relative,
          size: existingSize,
          preview: existingPreview,
        ),
        incoming: MmcConflictFile(
          relativePath: incoming.relative,
          size: incomingSize,
          preview: incomingPreview,
        ),
        identical: identical,
      );
    } finally {
      try {
        await source?.close();
      } finally {
        await written.close();
      }
    }
  }

  static bool _sameBytes(Uint8List left, Uint8List right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  static Future<void> _validateRuntime(
    String path,
    String name,
    MmcPackInfo info,
  ) async {
    if (info.components != null) {
      final profile = jsonDecode(
        await File(p.join(path, 'fml-mmc-profile.json')).readAsString(),
      );
      if (profile is! Map ||
          profile['fmlMmcProfileVersion'] != 1 ||
          profile['id'] != info.minecraft ||
          !await File(p.join(path, '$name.jar')).exists()) {
        throw StateError('安装结果缺少正确的 MMC 组件运行时');
      }
      return;
    }
    final vanilla = jsonDecode(
      await File(p.join(path, '$name.json')).readAsString(),
    );
    if (vanilla is! Map ||
        vanilla['id'] != info.minecraft ||
        !await File(p.join(path, '$name.jar')).exists()) {
      throw StateError('安装结果缺少正确的 Minecraft 运行时');
    }
    final loaderFile = switch (info.loader) {
      MmcLoader.vanilla => null,
      MmcLoader.fabric => 'fabric.json',
      MmcLoader.forge => 'Forge.json',
      MmcLoader.neoforge => 'NeoForge.json',
    };
    if (loaderFile != null) {
      final loader = jsonDecode(
        await File(p.join(path, loaderFile)).readAsString(),
      );
      if (loader is! Map) throw StateError('加载器安装结果无效');
    }
  }
}

class _GameEntry {
  const _GameEntry(this.relative, {this.sourcePath});

  final String relative;
  final String? sourcePath;
}

class _TargetEntry {
  _TargetEntry(
    this.output,
    this.relative, {
    required this.directory,
    this.reserved = false,
  });

  final String output;
  final String relative;
  final bool directory;
  final bool reserved;
  final children = <String, _TargetEntry>{};
}
