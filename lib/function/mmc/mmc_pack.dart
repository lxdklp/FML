import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'mmc_profile.dart';

enum MmcLoader {
  vanilla('Vanilla'),
  fabric('Fabric'),
  forge('Forge'),
  neoforge('NeoForge');

  const MmcLoader(this.configName);
  final String configName;
}

class MmcPackInfo {
  const MmcPackInfo({
    required this.name,
    required this.minecraft,
    required this.loader,
    this.loaderVersion,
    this.warnings = const [],
    this.worlds = const [],
    this.runtimeComponents = const {},
    this.components,
  });

  final String name;
  final String minecraft;
  final MmcLoader loader;
  final String? loaderVersion;
  final List<String> warnings;
  final List<String> worlds;
  final Map<String, String> runtimeComponents;
  final MmcComponentSet? components;
}

class MmcPack {
  const MmcPack({
    required this.info,
    required this.stagingPath,
    required this.fileCount,
    required this.expandedSize,
    this.gameFiles = const {},
    this.gameDirectories = const [],
    this.runtimePath,
  });

  final MmcPackInfo info;
  final String stagingPath;
  final int fileCount;
  final int expandedSize;
  final Map<String, String> gameFiles;
  final List<String> gameDirectories;
  final String? runtimePath;

  static Future<MmcPack> open(String path) => Isolate.run(() => _open(path));

  Future<void> dispose() async {
    for (final path in {stagingPath, ?runtimePath}) {
      final directory = Directory(path);
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }

  static MmcPack _open(String path) {
    final sourceSize = File(path).lengthSync();
    if (sourceSize > _maxArchiveSize) {
      throw const FormatException('MMC ZIP 超过 8 GiB');
    }
    final input = InputFileStream(path);
    Directory? staging;
    Directory? runtime;
    try {
      final entries = _readDirectory(input, sourceSize);
      final byName = {for (final entry in entries) entry.name: entry};
      final manifests = entries.where(
        (e) => p.posix.basename(e.name) == 'mmc-pack.json',
      );
      if (manifests.length != 1) {
        throw const FormatException('ZIP 必须包含且只能包含一个 MMC / Prism 实例');
      }
      final manifest = manifests.single;
      final parent = p.posix.dirname(manifest.name);
      final prefix = parent == '.' ? '' : '$parent/';
      if (parent != '.' && parent.contains('/')) {
        throw const FormatException('实例只能位于 ZIP 根目录或一层外部文件夹');
      }
      final config = byName['${prefix}instance.cfg'];
      if (manifest.isDirectory || config == null || config.isDirectory) {
        throw const FormatException('实例缺少 instance.cfg 或 mmc-pack.json');
      }
      if (entries.any(
        (e) => p.posix.basename(e.name) == 'instance.cfg' && e != config,
      )) {
        throw const FormatException('ZIP 包含多个实例配置');
      }
      final actualBudget = _SizeBudget();
      final configBytes = _decode(input, config, actualBudget, metadata: true)!;
      final manifestBytes = _decode(
        input,
        manifest,
        actualBudget,
        metadata: true,
      )!;
      final patches = <String, Map<String, dynamic>>{};
      final decodedMetadata = {config, manifest};
      for (final entry in entries) {
        if (!entry.name.startsWith(prefix) || entry.isDirectory) continue;
        final relative = entry.name.substring(prefix.length);
        final root = relative.split('/').first.toLowerCase();
        if (root == 'jarmods') {
          throw FormatException('暂不支持实例 jarmods: ${entry.name}');
        }
        if (root != 'patches') continue;
        if (!relative.startsWith('patches/') ||
            relative.split('/').length != 2 ||
            !relative.endsWith('.json')) {
          throw FormatException('实例 patch 路径无效: ${entry.name}');
        }
        final uid = p.posix.basenameWithoutExtension(relative);
        final value = jsonDecode(
          utf8.decode(_decode(input, entry, actualBudget, metadata: true)!),
        );
        if (value is! Map<String, dynamic>) {
          throw FormatException('实例 patch 必须是 JSON 对象: ${entry.name}');
        }
        patches[uid] = value;
        decodedMetadata.add(entry);
      }
      final manifestText = utf8.decode(manifestBytes);
      MmcComponentSet? components;
      MmcPackInfo parsed;
      if (patches.isEmpty) {
        parsed = _parseComponents(manifestText);
      } else {
        final manifestValue = jsonDecode(manifestText);
        if (manifestValue is! Map<String, dynamic>) {
          throw const FormatException('mmc-pack.json 必须是 JSON 对象');
        }
        components = MmcComponentSet(manifest: manifestValue, patches: patches);
        parsed = MmcPackInfo(
          name: '',
          minecraft: components.minecraft,
          loader: switch (components.loaderUid) {
            'net.fabricmc.fabric-loader' => MmcLoader.fabric,
            'net.minecraftforge' => MmcLoader.forge,
            'net.neoforged' => MmcLoader.neoforge,
            _ => MmcLoader.vanilla,
          },
          loaderVersion: components.loaderVersion,
          runtimeComponents: components.runtimeComponents,
        );
      }
      final name = _instanceName(
        utf8.decode(configBytes),
        p.basenameWithoutExtension(path),
      );
      final roots = ['${prefix}minecraft', '$prefix.minecraft'];
      bool hasContents(String root) =>
          entries.any((e) => e.name.startsWith('$root/'));
      if (roots.every(hasContents)) {
        throw const FormatException('minecraft 和 .minecraft 同时有内容, 无法确定游戏目录');
      }
      for (final root in roots) {
        if (byName[root] case final entry? when !entry.isDirectory) {
          throw FormatException('游戏目录实际是文件: $root');
        }
      }
      final gameRoot = roots.firstWhere(hasContents, orElse: () => roots.first);
      staging = Directory.systemTemp.createTempSync('fml-mmc-');
      var fileCount = 0;
      var expandedSize = 0;
      final worlds = <String>{};
      final gameFiles = <String, String>{};
      final gameDirectories = <String>{};
      for (final entry in entries) {
        if (decodedMetadata.contains(entry)) continue;
        final inGame = entry.name.startsWith('$gameRoot/');
        String? destination;
        if (inGame) {
          final relative = entry.name.substring(gameRoot.length + 1);
          _checkReserved(relative);
          final parts = relative.split('/');
          if (parts.first.toLowerCase() == 'saves' &&
              parts.length > 1 &&
              (parts.length > 2 || entry.isDirectory)) {
            worlds.add(parts[1]);
          }
          for (var length = 1; length < parts.length; length++) {
            gameDirectories.add(parts.take(length).join('/'));
          }
          if (entry.isDirectory) {
            gameDirectories.add(relative);
          } else {
            // 编号 blob 保留 ZIP 原始拼写, 由安装目标文件系统判断等价路径.
            final blob = 'files/${gameFiles.length}';
            destination = p.join(staging.path, blob);
            File(destination).parent.createSync(recursive: true);
            File(destination).createSync(exclusive: true);
            gameFiles[relative] = blob;
            fileCount++;
            expandedSize += entry.header.uncompressedSize;
          }
        } else if (entry.name.startsWith('${prefix}libraries/') &&
            !entry.isDirectory) {
          runtime ??= Directory.systemTemp.createTempSync('fml-mmc-runtime-');
          final relative = entry.name.substring(prefix.length);
          destination = p.joinAll([runtime.path, ...relative.split('/')]);
          File(destination).parent.createSync(recursive: true);
          File(destination).createSync(exclusive: true);
        }
        // 未迁移的文件也验证 CRC 和实际大小, 避免接受局部损坏的 ZIP.
        _decode(input, entry, actualBudget, destination: destination);
      }
      return MmcPack(
        info: MmcPackInfo(
          name: name,
          minecraft: parsed.minecraft,
          loader: parsed.loader,
          loaderVersion: parsed.loaderVersion,
          runtimeComponents: parsed.runtimeComponents,
          components: components,
          worlds: List.unmodifiable(worlds.toList()..sort()),
          warnings: const [
            '内存和窗口设置使用 FML 默认值, 不迁移 MMC / Prism 的实例设置。',
            '不迁移实例设置中的 Java 路径、额外 JVM 参数、环境变量和启动前后命令。组件声明的运行参数会保留。',
            '不迁移 MMC / Prism 账号、图标和启动器专用配置。',
          ],
        ),
        stagingPath: staging.path,
        fileCount: fileCount,
        expandedSize: expandedSize,
        gameFiles: Map.unmodifiable(gameFiles),
        gameDirectories: List.unmodifiable(gameDirectories),
        runtimePath: runtime?.path,
      );
    } catch (_) {
      staging?.deleteSync(recursive: true);
      runtime?.deleteSync(recursive: true);
      rethrow;
    } finally {
      input.closeSync();
    }
  }
}

const _maxArchiveSize = 8 * 1024 * 1024 * 1024;
const _maxExpandedSize = 32 * 1024 * 1024 * 1024;
const _maxEntries = 200000;
const _maxMetadataSize = 1024 * 1024;

class _ZipEntry {
  const _ZipEntry(this.header, this.name, this.isDirectory, this.dataOffset);
  final ZipFileHeader header;
  final String name;
  final bool isDirectory;
  final int dataOffset;
}

List<_ZipEntry> _readDirectory(InputFileStream input, int size) {
  if (size < 22) throw const FormatException('ZIP 已损坏或被截断');
  final tailStart = math.max(0, size - 65557);
  final tail = input
      .subset(position: tailStart, length: size - tailStart)
      .toUint8List();
  final bytes = ByteData.sublistView(tail);
  var end = -1;
  for (var i = tail.length - 22; i >= 0; i--) {
    if (bytes.getUint32(i, Endian.little) == ZipDirectory.eocdSignature &&
        i + 22 + bytes.getUint16(i + 20, Endian.little) == tail.length) {
      end = tailStart + i;
      break;
    }
  }
  if (end < 0) throw const FormatException('ZIP 缺少有效的中央目录');
  input.setPosition(end + 4);
  var disk = input.readUint16();
  var directoryDisk = input.readUint16();
  var diskEntries = input.readUint16();
  var count = input.readUint16();
  var directorySize = input.readUint32();
  var directoryOffset = input.readUint32();
  var directoryEnd = end;
  if (count == 0xffff ||
      directorySize == 0xffffffff ||
      directoryOffset == 0xffffffff) {
    if (end < 20) throw const FormatException('ZIP64 目录已损坏');
    input.setPosition(end - 20);
    if (input.readUint32() != ZipDirectory.zip64EocdLocatorSignature ||
        input.readUint32() != 0) {
      throw const FormatException('不支持分卷 ZIP 或损坏的 ZIP64');
    }
    final offset = input.readUint64();
    if (input.readUint32() != 1 || offset < 0 || offset + 56 > end - 20) {
      throw const FormatException('ZIP64 目录范围无效');
    }
    input.setPosition(offset);
    if (input.readUint32() != ZipDirectory.zip64EocdSignature) {
      throw const FormatException('ZIP64 目录签名无效');
    }
    final recordSize = input.readUint64();
    if (recordSize < 44 || offset + 12 + recordSize != end - 20) {
      throw const FormatException('ZIP64 目录大小无效');
    }
    input.skip(4);
    disk = input.readUint32();
    directoryDisk = input.readUint32();
    diskEntries = input.readUint64();
    count = input.readUint64();
    directorySize = input.readUint64();
    directoryOffset = input.readUint64();
    directoryEnd = offset;
  }
  if (disk != 0 || directoryDisk != 0 || diskEntries != count) {
    throw const FormatException('不支持分卷 ZIP');
  }
  if (count < 0 || count > _maxEntries) {
    throw const FormatException('ZIP 条目数量超过 200000');
  }
  if (directoryOffset < 0 ||
      directorySize < 0 ||
      directoryOffset + directorySize != directoryEnd) {
    throw const FormatException('ZIP 中央目录范围无效');
  }
  final directory = input.subset(
    position: directoryOffset,
    length: directorySize,
  );
  final entries = <_ZipEntry>[];
  final paths = <String, bool>{};
  final explicit = <String>{};
  final ranges = <(int, int)>[];
  var expanded = 0;
  for (var index = 0; index < count; index++) {
    if (directory.length < 46 ||
        directory.readUint32() != ZipFileHeader.signature) {
      throw const FormatException('ZIP 中央目录条目已损坏');
    }
    final recordStart = directory.position;
    directory.skip(24);
    final nameSize = directory.readUint16();
    final extraSize = directory.readUint16();
    final commentSize = directory.readUint16();
    directory.setPosition(recordStart);
    if (directory.length < 42 + nameSize + extraSize + commentSize) {
      throw const FormatException('ZIP 中央目录条目被截断');
    }
    final header = ZipFileHeader()..read(directory);
    final name = _relativePath(header.filename);
    final mode = (header.externalFileAttributes >> 16) & 0xf000;
    if (mode != 0 && mode != 0x8000 && mode != 0x4000) {
      throw FormatException('ZIP 不允许符号链接或特殊文件: $name');
    }
    final isDirectory =
        header.filename.endsWith('/') ||
        mode == 0x4000 ||
        (header.externalFileAttributes & 0x10 != 0);
    _checkHeader(header, name);
    if (isDirectory && header.uncompressedSize != 0) {
      throw FormatException('ZIP 目录包含文件数据: $name');
    }
    expanded += header.uncompressedSize;
    if (expanded > _maxExpandedSize) {
      throw const FormatException('ZIP 解压大小超过 32 GiB');
    }
    if (!explicit.add(name)) {
      throw FormatException('ZIP 包含重复路径: $name');
    }
    final parts = name.split('/');
    for (var i = 1; i <= parts.length; i++) {
      final ancestor = parts.take(i).join('/');
      final key = ancestor;
      final directoryNode = i < parts.length || isDirectory;
      if (paths[key] != null && paths[key] != directoryNode) {
        throw FormatException('ZIP 文件与目录冲突: $name');
      }
      paths[key] = directoryNode;
    }
    final range = _localDataRange(input, header, directoryOffset);
    ranges.add((header.localHeaderOffset, range.$2));
    entries.add(_ZipEntry(header, name, isDirectory, range.$1));
  }
  if (!directory.isEOS) throw const FormatException('ZIP 中央目录条目数量不一致');
  ranges.sort((a, b) => a.$1.compareTo(b.$1));
  for (var i = 1; i < ranges.length; i++) {
    if (ranges[i].$1 < ranges[i - 1].$2) {
      throw const FormatException('ZIP 条目数据范围重叠');
    }
  }
  return entries;
}

void _checkHeader(ZipFileHeader header, String name) {
  if (header.generalPurposeBitFlag & 0x41 != 0) {
    throw const FormatException('不支持加密 ZIP');
  }
  if (!const {0, 8}.contains(header.compressionMethod)) {
    throw FormatException('不支持的 ZIP 压缩方法: $name');
  }
  if (header.diskNumberStart != 0 ||
      header.uncompressedSize < 0 ||
      header.compressedSize < 0 ||
      header.localHeaderOffset < 0) {
    throw const FormatException('ZIP 条目大小或分卷信息无效');
  }
}

(int, int) _localDataRange(
  InputFileStream input,
  ZipFileHeader header,
  int limit,
) {
  if (header.localHeaderOffset + 30 > limit) {
    throw const FormatException('ZIP 本地文件头范围无效');
  }
  input.setPosition(header.localHeaderOffset);
  if (input.readUint32() != ZipFile.zipSignature) {
    throw const FormatException('ZIP 本地文件头签名无效');
  }
  input.skip(2);
  final flags = input.readUint16();
  final method = input.readUint16();
  input.skip(4);
  final crc = input.readUint32();
  final compressed = input.readUint32();
  final expanded = input.readUint32();
  final nameLength = input.readUint16();
  final extraLength = input.readUint16();
  final dataOffset = input.position + nameLength + extraLength;
  if (dataOffset + header.compressedSize > limit ||
      flags != header.generalPurposeBitFlag ||
      method != header.compressionMethod ||
      input.readString(size: nameLength) != header.filename ||
      (flags & 8 == 0 &&
          (crc != header.crc32 ||
              (compressed != 0xffffffff &&
                  compressed != header.compressedSize) ||
              (expanded != 0xffffffff &&
                  expanded != header.uncompressedSize)))) {
    throw FormatException('ZIP 本地文件头与中央目录不一致: ${header.filename}');
  }
  var end = dataOffset + header.compressedSize;
  if (flags & 8 != 0) {
    if (end + 12 > limit) {
      throw const FormatException('ZIP data descriptor 被截断');
    }
    input.setPosition(end);
    var descriptorCrc = input.readUint32();
    if (descriptorCrc == 0x08074b50) {
      descriptorCrc = input.readUint32();
    }
    final sizeOffset = input.position;
    var descriptorCompressed = input.readUint32();
    var descriptorExpanded = input.readUint32();
    if (compressed == 0xffffffff ||
        expanded == 0xffffffff ||
        descriptorCompressed != header.compressedSize ||
        descriptorExpanded != header.uncompressedSize) {
      input.setPosition(sizeOffset);
      descriptorCompressed = input.readUint64();
      descriptorExpanded = input.readUint64();
    }
    end = input.position;
    if (end > limit ||
        descriptorCrc != header.crc32 ||
        descriptorCompressed != header.compressedSize ||
        descriptorExpanded != header.uncompressedSize) {
      throw const FormatException('ZIP data descriptor 与中央目录不一致');
    }
  }
  return (dataOffset, end);
}

class _SizeBudget {
  int actual = 0;
}

class _CheckedSink implements Sink<List<int>> {
  _CheckedSink(this.entry, this.budget, {this.output, this.memory});
  final _ZipEntry entry;
  final _SizeBudget budget;
  final OutputFileStream? output;
  final BytesBuilder? memory;
  int length = 0;
  int crc = 0;

  @override
  void add(List<int> data) {
    length += data.length;
    budget.actual += data.length;
    if (length > entry.header.uncompressedSize ||
        budget.actual > _maxExpandedSize ||
        (memory != null && length > _maxMetadataSize)) {
      throw FormatException('ZIP 实际解压大小超过限制: ${entry.name}');
    }
    crc = getCrc32(data, crc);
    output?.writeBytes(data);
    memory?.add(data);
  }

  @override
  void close() {}
}

Uint8List? _decode(
  InputFileStream input,
  _ZipEntry entry,
  _SizeBudget budget, {
  String? destination,
  bool metadata = false,
}) {
  if (metadata && entry.header.uncompressedSize > _maxMetadataSize) {
    throw FormatException('MMC 元数据超过 1 MiB: ${entry.name}');
  }
  final output = destination != null && !entry.isDirectory
      ? OutputFileStream(destination)
      : null;
  final memory = metadata ? BytesBuilder(copy: false) : null;
  final checked = _CheckedSink(entry, budget, output: output, memory: memory);
  try {
    final content = input.subset(
      position: entry.dataOffset,
      length: entry.header.compressedSize,
    );
    // archive 4.0.7 的 native decodeStream 会聚合完整输出, 此处直接连接分块 sink.
    final sink = entry.header.compressionMethod == 8
        ? ZLibCodec(raw: true).decoder.startChunkedConversion(checked)
        : checked;
    while (!content.isEOS) {
      sink.add(content.readBytes(math.min(1024, content.length)).toUint8List());
    }
    sink.close();
    if (checked.length != entry.header.uncompressedSize ||
        checked.crc != entry.header.crc32) {
      throw FormatException('ZIP 文件大小或 CRC 校验失败: ${entry.name}');
    }
    return memory?.takeBytes();
  } finally {
    output?.closeSync();
  }
}

MmcPackInfo _parseComponents(String text) {
  final value = jsonDecode(text);
  if (value is! Map ||
      value['formatVersion'] != 1 ||
      value['components'] is! List) {
    throw const FormatException('不支持的 mmc-pack.json 格式, 需要 formatVersion=1');
  }
  String? minecraft;
  String? intermediary;
  MmcLoader loader = MmcLoader.vanilla;
  String? loaderVersion;
  final runtime = <String, String>{};
  final seen = <String>{};
  for (final component in value['components'] as List) {
    if (component is! Map ||
        (component['disabled'] != null && component['disabled'] is! bool)) {
      throw const FormatException('实例组件格式无效');
    }
    if (component['disabled'] == true) continue;
    final uid = component['uid'];
    final version = component['version'];
    if (uid is! String ||
        version is! String ||
        version.trim().isEmpty ||
        !seen.add(uid)) {
      throw const FormatException('活动组件缺少精确版本、UID 或存在重复组件');
    }
    switch (uid) {
      case 'net.minecraft':
        minecraft = version;
      case 'net.fabricmc.intermediary':
        intermediary = version;
      case 'org.lwjgl':
      case 'org.lwjgl3':
        runtime[uid] = version;
      case 'net.fabricmc.fabric-loader':
      case 'net.minecraftforge':
      case 'net.neoforged':
        if (loader != MmcLoader.vanilla) {
          throw const FormatException('实例包含多个活动模组加载器');
        }
        loader = switch (uid) {
          'net.fabricmc.fabric-loader' => MmcLoader.fabric,
          'net.minecraftforge' => MmcLoader.forge,
          _ => MmcLoader.neoforge,
        };
        loaderVersion = version;
      default:
        throw FormatException('暂不支持的活动实例组件: $uid');
    }
  }
  if (minecraft == null) throw const FormatException('实例缺少活动 Minecraft 精确版本');
  if (intermediary != null &&
      (loader != MmcLoader.fabric || intermediary != minecraft)) {
    throw const FormatException(
      'Fabric intermediary 必须用于 Fabric 且版本与 Minecraft 一致',
    );
  }
  return MmcPackInfo(
    name: '',
    minecraft: minecraft,
    loader: loader,
    loaderVersion: loaderVersion,
    runtimeComponents: Map.unmodifiable(runtime),
  );
}

String _instanceName(String text, String fallback) {
  var section = '';
  String? name;
  final logical = text.replaceAll('\\\r\n', '').replaceAll('\\\n', '');
  for (final line in const LineSplitter().convert(
    logical.replaceFirst('\ufeff', ''),
  )) {
    final trimmed = line.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      section = trimmed.substring(1, trimmed.length - 1);
      continue;
    }
    if (trimmed.isEmpty || trimmed.startsWith(';') || trimmed.startsWith('#')) {
      continue;
    }
    final equal = trimmed.indexOf('=');
    if (equal < 0 || (section != '' && section != 'General')) continue;
    if (trimmed.substring(0, equal).trim() == 'name') {
      name = _qtString(trimmed.substring(equal + 1).trim());
    }
  }
  return name == null || name.trim().isEmpty ? fallback : name;
}

String _qtString(String value) {
  final result = StringBuffer();
  var quoted = false;
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (char == '"') {
      quoted = !quoted;
    } else if (char == ';' && !quoted) {
      break;
    } else if (char == '\\' && i + 1 < value.length) {
      final escaped = value[++i];
      if (escaped == 'x') {
        final hex = StringBuffer();
        while (i + 1 < value.length &&
            RegExp(r'[0-9a-fA-F]').hasMatch(value[i + 1])) {
          hex.write(value[++i]);
        }
        if (hex.isNotEmpty) {
          result.writeCharCode(int.parse(hex.toString(), radix: 16) & 0xffff);
        }
      } else {
        result.write(
          const {
                'n': '\n',
                'r': '\r',
                't': '\t',
                'b': '\b',
                'f': '\f',
                'v': '\v',
                'a': '\x07',
              }[escaped] ??
              escaped,
        );
      }
    } else {
      result.write(char);
    }
  }
  var name = result.toString();
  if (name.startsWith('@@')) name = name.substring(1);
  if (name.startsWith('@String(') && name.endsWith(')')) {
    name = name.substring(8, name.length - 1);
  }
  return name;
}

String _relativePath(String value) {
  final name = value.endsWith('/')
      ? value.substring(0, value.length - 1)
      : value;
  if (name.isEmpty ||
      name.length > 4096 ||
      name.split('/').length > 256 ||
      name.contains('\\') ||
      name.startsWith('/') ||
      name
          .split('/')
          .any(
            (part) =>
                part.isEmpty ||
                part.length > 255 ||
                part == '.' ||
                part == '..' ||
                part.endsWith('.') ||
                part.endsWith(' ') ||
                RegExp(r'[\x00-\x1f\x7f:<>"|?*]').hasMatch(part) ||
                RegExp(
                  r'^(con|prn|aux|nul|com[1-9¹²³]|lpt[1-9¹²³])(?:\.|$)',
                  caseSensitive: false,
                ).hasMatch(part),
          )) {
    throw FormatException('ZIP 包含不安全的路径: $value');
  }
  return name;
}

void _checkReserved(String name) {
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
    'fml-mmc-profile.json',
    '.fml-mmc-runtime',
    'mrpack',
    'curseforge',
    'patchpackinfo.json',
  }.contains(name.split('/').first.toLowerCase())) {
    throw FormatException('游戏内容包含 FML 启动保留路径: $name');
  }
}
