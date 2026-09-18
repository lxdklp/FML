import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:fml/constants.dart';
import 'package:fml/function/dio_client.dart';

import 'forge_metadata.dart';
import 'forge_service.dart';

enum ForgePackSource { modrinth, curseforge }

class ForgePackManifest {
  const ForgePackManifest(this.minecraft, this.forge);
  final String minecraft;
  final String forge;

  factory ForgePackManifest.parse(Map manifest, ForgePackSource source) {
    String minecraft;
    String forge;
    if (source == ForgePackSource.modrinth) {
      if (manifest['game'] != 'minecraft' || manifest['formatVersion'] != 1) {
        throw const FormatException('不支持的 Modrinth 整合包格式');
      }
      final dependencies = manifest['dependencies'] as Map? ?? {};
      minecraft = dependencies['minecraft'] as String? ?? '';
      forge = dependencies['forge'] as String? ?? '';
      if (dependencies.keys.any((k) => k != 'minecraft' && k != 'forge')) {
        throw const FormatException('整合包包含无法与 Forge 一起安装的依赖');
      }
    } else {
      final game = manifest['minecraft'] as Map? ?? {};
      minecraft = game['version'] as String? ?? '';
      final loaders = (game['modLoaders'] as List? ?? []).cast<Map>();
      final loader =
          loaders.where((v) => v['primary'] == true).firstOrNull ??
          loaders.firstOrNull;
      final id = loader?['id'] as String? ?? '';
      forge = id.startsWith('forge-') ? id.substring(6) : '';
    }
    if (minecraft.isEmpty || forge.isEmpty) {
      throw const FormatException('整合包清单缺少 Minecraft 或 Forge 版本');
    }
    return ForgePackManifest(minecraft, forge);
  }
}

class ForgeModpackInstaller {
  ForgeModpackInstaller(this.installer);
  final ForgeInstaller installer;

  Future<void> install(String url, ForgePackSource source) async {
    late Archive archive;
    late Map<String, dynamic> manifest;
    late ForgePackManifest version;
    await installer.stage('正在下载整合包', () async {
      final path = p.join(installer.instancePath, 'forge-modpack.zip');
      await ForgeInstaller.download(
        url,
        path,
        progress: (v) => installer.onProgress('正在下载整合包', v),
      );
      archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
    });
    await installer.stage('正在解析整合包', () async {
      manifest = ForgeInstaller.archiveJson(
        archive,
        source == ForgePackSource.modrinth
            ? 'modrinth.index.json'
            : 'manifest.json',
      );
      version = ForgePackManifest.parse(manifest, source);
    });
    final build = await ForgeVersions.resolve(version.minecraft, version.forge);
    await installer.install(minecraft: version.minecraft, build: build);
    await installer.stage('正在下载整合包文件', () async {
      if (source == ForgePackSource.modrinth) {
        await _modrinthFiles(manifest);
      } else {
        await _curseforgeFiles(manifest);
      }
    });
    await installer.stage('正在复制整合包配置', () async {
      final directories = source == ForgePackSource.modrinth
          ? ['overrides', 'client-overrides']
          : [manifest['overrides'] as String? ?? 'overrides'];
      for (final directory in directories) {
        safeChild(installer.instancePath, directory);
        final prefix =
            '${directory.replaceAll('\\', '/').replaceFirst(RegExp(r'/+$'), '')}/';
        for (final file in archive.files.where(
          (f) => f.name.startsWith(prefix) && f.isFile,
        )) {
          if (file.isSymbolicLink) throw const FormatException('整合包包含不支持的符号链接');
          final destination = File(
            _packPath(file.name.substring(prefix.length)),
          );
          await destination.parent.create(recursive: true);
          await destination.writeAsBytes(file.content);
        }
      }
    });
  }

  String _packPath(String path) {
    final reserved = [
      'Forge.json',
      '${installer.name}.json',
      '${installer.name}.jar',
      'forge-installer.jar',
      'forge-modpack.zip',
    ];
    final result = safeChild(installer.instancePath, path);
    final relative = p.relative(result, from: installer.instancePath);
    if (reserved.any((v) => v.toLowerCase() == relative.toLowerCase())) {
      throw FormatException('整合包文件与启动配置冲突: $path');
    }
    return result;
  }

  Future<void> _modrinthFiles(Map manifest) async {
    final files = (manifest['files'] as List? ?? [])
        .cast<Map>()
        .where((v) => v['env']?['client'] != 'unsupported')
        .toList();
    await ForgeInstaller.parallel(files, (file) async {
      final path = _packPath(file['path']);
      final urls = (file['downloads'] as List? ?? []).cast<String>();
      final hash = file['hashes']?['sha1'] as String?;
      final sha512Hash = file['hashes']?['sha512'] as String?;
      if (urls.isEmpty ||
          ((hash?.isEmpty ?? true) && (sha512Hash?.isEmpty ?? true))) {
        throw FormatException('整合包文件缺少下载地址或 SHA 校验值: ${file['path']}');
      }
      try {
        await ForgeInstaller.download(
          urls.first,
          path,
          hash: hash,
          sha512Hash: sha512Hash,
          fallbackUrls: urls.skip(1).toList(),
        );
      } catch (e) {
        throw StateError('整合包文件下载失败: ${file['path']}，$e');
      }
    }, progress: (v) => installer.onProgress('正在下载整合包文件', v));
  }

  Future<void> _curseforgeFiles(Map manifest) async {
    final files = (manifest['files'] as List? ?? []).cast<Map>().toList();
    final options = Options(headers: {'x-api-key': kCurseforgeApiKey});
    await ForgeInstaller.parallel(files, (entry) async {
      final project = entry['projectID'];
      final id = entry['fileID'];
      final response = await DioClient().dio.get(
        'https://api.curseforge.com/v1/mods/$project/files/$id',
        options: options,
      );
      final file = response.data['data'] as Map;
      final url = file['downloadUrl'] as String?;
      if (url == null || url.isEmpty) {
        throw StateError(
          'CurseForge 文件 ${file['fileName']}（$project/$id）不允许第三方下载，无法完成安装',
        );
      }
      final mod = await DioClient().dio.get(
        'https://api.curseforge.com/v1/mods/$project',
        options: options,
      );
      final folder = switch (mod.data['data']['classId']) {
        12 => 'resourcepacks',
        6552 => 'shaderpacks',
        _ => 'mods',
      };
      final hashes = (file['hashes'] as List? ?? []).cast<Map>();
      final sha =
          hashes.where((v) => v['algo'] == 1).firstOrNull?['value'] as String?;
      if (sha == null || sha.isEmpty) {
        throw StateError('整合包文件缺少 SHA 校验值: ${file['fileName']}');
      }
      await ForgeInstaller.download(
        url,
        _packPath('$folder/${file['fileName']}'),
        hash: sha,
      );
    }, progress: (v) => installer.onProgress('正在下载整合包文件', v));
  }
}
