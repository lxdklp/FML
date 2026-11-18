import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../forge/forge_metadata.dart';
import '../forge/forge_service.dart';

Future<void> installInstanceRuntime({
  required String gamePath,
  required String name,
  String? instancePath,
  required String minecraft,
  required String loader,
  String? loaderVersion,
  Map<String, String> runtimeComponents = const {},
  required void Function(String, double?) onProgress,
  required void Function() checkCancelled,
  required String javaExecutable,
}) => InstanceRuntimeInstaller().install(
  gamePath: gamePath,
  name: name,
  instancePath: instancePath,
  minecraft: minecraft,
  loader: loader,
  loaderVersion: loaderVersion,
  runtimeComponents: runtimeComponents,
  onProgress: onProgress,
  checkCancelled: checkCancelled,
  javaExecutable: javaExecutable,
);

/// 注入网络和进程依赖
class InstanceRuntimeInstaller {
  InstanceRuntimeInstaller({
    ForgeJsonLoader? jsonLoader,
    ForgeFileDownloader? fileDownloader,
    ForgeChecksumLoader? checksumLoader,
    Future<ForgeBuild> Function(String, String)? resolveForge,
    this.processorRunner,
  }) : jsonLoader = jsonLoader ?? ForgeInstaller.jsonUrl,
       fileDownloader = fileDownloader ?? ForgeInstaller.download,
       checksumLoader = checksumLoader ?? ForgeInstaller.installerChecksum,
       resolveForge = resolveForge ?? ForgeVersions.resolve;

  final ForgeJsonLoader jsonLoader;
  final ForgeFileDownloader fileDownloader;
  final ForgeChecksumLoader checksumLoader;
  final Future<ForgeBuild> Function(String, String) resolveForge;
  final ForgeProcessorRunner? processorRunner;

  // 安装实例运行时
  Future<void> install({
    required String gamePath,
    required String name,
    String? instancePath,
    required String minecraft,
    required String loader,
    String? loaderVersion,
    Map<String, String> runtimeComponents = const {},
    required void Function(String, double?) onProgress,
    required void Function() checkCancelled,
    required String javaExecutable,
  }) async {
    checkCancelled();
    if (!const ['Vanilla', 'Fabric', 'Forge', 'NeoForge'].contains(loader)) {
      throw UnsupportedError('不支持的模组加载器: $loader');
    }
    if (loader != 'Vanilla' &&
        (loaderVersion == null || loaderVersion.trim().isEmpty)) {
      throw const FormatException('缺少模组加载器版本');
    }
    final installer = ForgeInstaller(
      gamePath: gamePath,
      name: name,
      instanceDirectory: instancePath,
      onProgress: onProgress,
      javaExecutable: javaExecutable,
      checkCancelled: checkCancelled,
      jsonLoader: jsonLoader,
      fileDownloader: fileDownloader,
      checksumLoader: checksumLoader,
      processorRunner: processorRunner,
      logStages: false,
    );
    final vanilla = await installer.installVanilla(
      minecraft: minecraft,
      validateMetadata: (metadata) =>
          validateRuntimeComponents(metadata, runtimeComponents),
    );
    checkCancelled();
    if (loader == 'Vanilla') return;
    if (loader == 'Fabric') {
      await _fabric(installer, minecraft, loaderVersion!, checkCancelled);
      return;
    }
    if (loader == 'Forge') {
      final build = await resolveForge(minecraft, loaderVersion!);
      checkCancelled();
      if (build.version != loaderVersion &&
          build.coordinate != loaderVersion &&
          build.coordinate != '$minecraft-$loaderVersion') {
        throw StateError('Forge 解析结果与请求版本不匹配');
      }
      await installer.installLoader(
        minecraft: minecraft,
        vanilla: vanilla,
        installerUrl: build.installerUrl,
        expectedCoordinate: 'net.minecraftforge:forge:${build.coordinate}',
      );
      return;
    }
    final legacy = minecraft == '1.20.1';
    final artifact = legacy ? 'forge' : 'neoforge';
    final version = legacy && !loaderVersion!.startsWith('$minecraft-')
        ? '$minecraft-$loaderVersion'
        : loaderVersion!;
    // 两代 NeoForge 使用不同坐标, 不通过原版安装器写入整个游戏根目录.
    final url =
        'https://maven.neoforged.net/releases/net/neoforged/'
        '$artifact/$version/$artifact-$version-installer.jar';
    await installer.installLoader(
      minecraft: minecraft,
      vanilla: vanilla,
      installerUrl: url,
      loaderName: 'NeoForge',
      expectedCoordinate: 'net.neoforged:$artifact:$version',
    );
  }

  // 校验运行库组件是否与原版一致
  static void validateRuntimeComponents(
    Map<String, dynamic> vanilla,
    Map<String, String> components,
  ) {
    for (final component in components.entries) {
      if (component.key != 'org.lwjgl' && component.key != 'org.lwjgl3') {
        throw UnsupportedError('不支持的运行库组件: ${component.key}');
      }
      final group = component.key == 'org.lwjgl'
          ? 'org.lwjgl.lwjgl'
          : 'org.lwjgl';
      final versions = <String>{
        for (final library in vanilla['libraries'] as List? ?? [])
          if (library['name'] is String &&
              (library['name'] as String).split(':').length >= 3 &&
              (library['name'] as String).split(':')[0] == group)
            (library['name'] as String).split(':')[2],
      };
      if (versions.length != 1 || !versions.contains(component.value)) {
        throw UnsupportedError(
          '不支持自定义运行库 ${component.key}:${component.value}, '
          'Minecraft 默认版本为 ${versions.isEmpty ? "未提供" : versions.join(", ")}',
        );
      }
    }
  }

  // 运行时安装器
  Future<void> _fabric(
    ForgeInstaller installer,
    String minecraft,
    String version,
    void Function() checkCancelled,
  ) async {
    await installer.stage('正在读取 Fabric 版本', () async {
      final metadata = await jsonLoader(
        'https://meta.fabricmc.net/v2/versions/loader/'
        '${Uri.encodeComponent(minecraft)}/${Uri.encodeComponent(version)}',
      );
      checkCancelled();
      if (metadata['loader']?['version'] != version ||
          metadata['loader']?['maven'] !=
              'net.fabricmc:fabric-loader:$version' ||
          metadata['intermediary']?['version'] != minecraft ||
          metadata['intermediary']?['maven'] !=
              'net.fabricmc:intermediary:$minecraft' ||
          metadata['launcherMeta']?['libraries'] is! Map) {
        throw StateError('Fabric 元数据与请求的 Minecraft 或加载器版本不匹配');
      }
      final launcherLibraries = metadata['launcherMeta']['libraries'] as Map;
      final libraries = <Map>[
        {
          'name': metadata['loader']['maven'],
          'url': 'https://maven.fabricmc.net/',
        },
        {
          'name': metadata['intermediary']['maven'],
          'url': 'https://maven.fabricmc.net/',
        },
        ...?launcherLibraries['common'] as List?,
        ...?launcherLibraries['client'] as List?,
      ];
      await installer.stage('正在下载 Fabric 运行库', () async {
        await ForgeInstaller.parallel(libraries, (library) async {
          checkCancelled();
          final artifact = libraryArtifact(library);
          if (artifact == null || (artifact['url'] as String? ?? '').isEmpty) {
            throw const FormatException('Fabric 运行库缺少下载信息');
          }
          final url = artifact['url'] as String;
          final hash =
              artifact['sha1'] as String? ??
              library['sha1'] as String? ??
              await checksumLoader(url);
          checkCancelled();
          if (!RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(hash)) {
            throw const FormatException('Fabric 运行库 SHA1 无效');
          }
          final path = safeChild(installer.librariesPath, artifact['path']);
          await fileDownloader(url, path, hash: hash, fallbackUrls: const []);
          checkCancelled();
          if (!await ForgeInstaller.validFile(path, hash: hash)) {
            throw StateError('Fabric 运行库校验失败: ${library['name']}');
          }
        }, progress: (v) => installer.onProgress('正在下载 Fabric 运行库', v));
      });
      checkCancelled();
      await File(p.join(installer.instancePath, 'fabric.json'))
          .writeAsString(jsonEncode(metadata));
    });
  }
}
