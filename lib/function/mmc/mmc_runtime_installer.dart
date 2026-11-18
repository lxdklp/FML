import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../forge/forge_metadata.dart';
import '../forge/forge_service.dart';

typedef MmcCustomRuntimeInstaller = Future<void> Function({
  required String gamePath,
  required String instancePath,
  required String name,
  required Map<String, dynamic> profile,
  String? runtimePath,
  required void Function(String, double?) onProgress,
  required void Function() checkCancelled,
  required String javaExecutable,
});

Future<void> installMmcRuntime({
  required String gamePath,
  required String instancePath,
  required String name,
  required Map<String, dynamic> profile,
  String? runtimePath,
  required void Function(String, double?) onProgress,
  required void Function() checkCancelled,
  required String javaExecutable,
}) => MmcRuntimeInstaller().install(
  gamePath: gamePath,
  instancePath: instancePath,
  name: name,
  profile: profile,
  runtimePath: runtimePath,
  onProgress: onProgress,
  checkCancelled: checkCancelled,
  javaExecutable: javaExecutable,
);

class MmcRuntimeInstaller {
  MmcRuntimeInstaller({
    ForgeJsonLoader? jsonLoader,
    ForgeFileDownloader? fileDownloader,
    this.logStages = false,
  }) : jsonLoader = jsonLoader ?? ForgeInstaller.jsonUrl,
       fileDownloader = fileDownloader ?? ForgeInstaller.download;

  final ForgeJsonLoader jsonLoader;
  final ForgeFileDownloader fileDownloader;
  final bool logStages;

  Future<void> install({
    required String gamePath,
    required String instancePath,
    required String name,
    required Map<String, dynamic> profile,
    String? runtimePath,
    required void Function(String, double?) onProgress,
    required void Function() checkCancelled,
    required String javaExecutable,
  }) async {
    checkCancelled();
    if (instanceNameError(name) case final String error) {
      throw FormatException(error);
    }
    // 深复制后只写实例相对路径, 保持解析结果和临时解包目录互相独立.
    final installed = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(profile)),
    );
    final libraries = (installed['libraries'] as List).cast<Map>();
    final localArtifacts = <Map>[];
    for (final library in libraries) {
      checkCancelled();
      final downloads = library['downloads'] as Map?;
      final classifiers = downloads?['classifiers'] as Map?;
      if (classifiers != null &&
          classifiers.values.any(
            (entry) => entry is Map && entry['mmcLocal'] != null,
          )) {
        throw FormatException('尚不支持 MMC 本地原生运行库: ${library['name']}');
      }
      final artifact = downloads?['artifact'];
      if (artifact is Map && artifact['mmcLocal'] != null) {
        localArtifacts.add(artifact);
      }
    }
    if (installed['downloads']?['client']?['mmcLocal'] != null) {
      throw const FormatException('尚不支持 MMC 本地客户端文件');
    }
    if (localArtifacts.isNotEmpty && runtimePath == null) {
      throw const FormatException('MMC 整合包缺少本地运行库目录');
    }
    if (localArtifacts.isNotEmpty) onProgress('正在校验本地运行库', null);
    for (var i = 0; i < localArtifacts.length; i++) {
      checkCancelled();
      final artifact = localArtifacts[i];
      final sourceRoot = runtimePath!;
      final source = safeChild(sourceRoot, 'libraries/${artifact['mmcLocal']}');
      await _requireRegularPath(sourceRoot, source);
      final digest = await _verify(
        source,
        hash: artifact['sha1'],
        size: artifact['size'],
        checkCancelled: checkCancelled,
      );
      final relative = '.fml-mmc-runtime/${artifact['path']}';
      final target = safeChild(instancePath, relative);
      await _requireRegularPath(instancePath, target, allowMissing: true);
      await Directory(p.dirname(target)).create(recursive: true);
      checkCancelled();
      final sink = File(target).openWrite();
      try {
        await sink.addStream(
          File(source).openRead().map((bytes) {
            checkCancelled();
            return bytes;
          }),
        );
      } finally {
        await sink.close();
      }
      await _verify(
        target,
        hash: digest,
        size: await File(source).length(),
        checkCancelled: checkCancelled,
      );
      artifact.remove('url');
      artifact['mmcLocalPath'] = relative;
      artifact['sha1'] = digest;
      artifact['size'] = await File(target).length();
      onProgress('正在校验本地运行库', (i + 1) / localArtifacts.length);
    }
    checkCancelled();
    final installer = ForgeInstaller(
      gamePath: gamePath,
      instanceDirectory: instancePath,
      name: name,
      javaExecutable: javaExecutable,
      onProgress: onProgress,
      checkCancelled: checkCancelled,
      jsonLoader: jsonLoader,
      logStages: logStages,
      fileDownloader:
          (
            url,
            path, {
            hash,
            sha512Hash,
            size,
            required fallbackUrls,
            progress,
          }) async {
            checkCancelled();
            await fileDownloader(
              url,
              path,
              hash: hash,
              sha512Hash: sha512Hash,
              size: size,
              fallbackUrls: {
                ...fallbackUrls,
                ..._mavenCentralFallback(url, hash, sha512Hash),
              }.toList(),
              progress: progress,
            );
            await _verify(
              path,
              hash: hash,
              sha512Hash: sha512Hash,
              size: size,
              checkCancelled: checkCancelled,
            );
          },
    );
    await installer.installMetadata(installed);
    checkCancelled();
    final encoded = jsonEncode(installed);
    await File(p.join(instancePath, '$name.json')).writeAsString(encoded);
    checkCancelled();
    await File(p.join(instancePath, 'fml-mmc-profile.json'))
        .writeAsString(encoded);
    checkCancelled();
  }
}

List<String> _mavenCentralFallback(
  String url,
  String? hash,
  String? sha512Hash,
) {
  final hasChecksum =
      (hash != null && RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(hash)) ||
      (sha512Hash != null &&
          RegExp(r'^[a-fA-F0-9]{128}$').hasMatch(sha512Hash));
  if (!hasChecksum) return const [];
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !const {'repo1.maven.org', 'repo.maven.apache.org'}.contains(uri.host) ||
      !uri.path.startsWith('/maven2/')) {
    return const [];
  }
  // 只为有发布校验值的 Maven Central 文件添加官方镜像, 保持原 URL 优先.
  return [
    uri
        .replace(
          scheme: 'https',
          host: 'maven-central.storage-download.googleapis.com',
          port: 443,
          userInfo: '',
        )
        .toString(),
  ];
}

Future<String> _verify(
  String path, {
  String? hash,
  String? sha512Hash,
  int? size,
  required void Function() checkCancelled,
}) async {
  checkCancelled();
  final file = File(path);
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw FormatException('MMC 运行时文件不存在或不是普通文件: ${p.basename(path)}');
  }
  final length = await file.length();
  if (length == 0 || (size != null && (size < 0 || length != size))) {
    throw FormatException('MMC 运行时文件大小校验失败: ${p.basename(path)}');
  }
  final actual =
      (await sha1
              .bind(
                file.openRead().map((bytes) {
                  checkCancelled();
                  return bytes;
                }),
              )
              .single)
          .toString();
  if (hash != null && actual != hash.toLowerCase()) {
    throw FormatException('MMC 运行时文件 SHA1 校验失败: ${p.basename(path)}');
  }
  if (sha512Hash != null) {
    final actual512 = (await sha512.bind(file.openRead()).single).toString();
    if (actual512 != sha512Hash.toLowerCase()) {
      throw FormatException('MMC 运行时文件 SHA512 校验失败: ${p.basename(path)}');
    }
  }
  checkCancelled();
  return actual;
}

Future<void> _requireRegularPath(
  String root,
  String target, {
  bool allowMissing = false,
}) async {
  final parts = p.split(p.relative(target, from: root));
  var current = root;
  for (var i = -1; i < parts.length; i++) {
    if (i >= 0) current = p.join(current, parts[i]);
    final type = await FileSystemEntity.type(current, followLinks: false);
    if (allowMissing && type == FileSystemEntityType.notFound) continue;
    final expected = i == parts.length - 1
        ? FileSystemEntityType.file
        : FileSystemEntityType.directory;
    if (type != expected) {
      throw FormatException('MMC 本地运行库路径不存在或包含符号链接: ${p.basename(current)}');
    }
  }
}
