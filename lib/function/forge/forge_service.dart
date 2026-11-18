import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:fml/function/config/app_config.dart';
import 'package:fml/function/dio_client.dart';
import 'package:fml/function/download.dart';
import 'package:fml/function/java/java_launch_check.dart';
import 'package:fml/function/log.dart';

import 'forge_metadata.dart';

typedef ForgeProgress = void Function(String stage, double? progress);
typedef ForgeJsonLoader = Future<Map<String, dynamic>> Function(String url);
typedef ForgeChecksumLoader = Future<String> Function(String url);
typedef ForgeFileDownloader = Future<void> Function(
  String url,
  String path, {
  String? hash,
  String? sha512Hash,
  int? size,
  required List<String> fallbackUrls,
  void Function(double)? progress,
});
typedef ForgeProcessorRunner = Future<void> Function(
  String java,
  List<String> args,
  String workingDirectory,
);

void _noCancellation() {}

class ForgeBuild {
  const ForgeBuild(this.version, this.coordinate, {this.recommended = false});
  final String version;
  final String coordinate;
  final bool recommended;

  String get installerUrl =>
      'https://maven.minecraftforge.net/net/minecraftforge/forge/'
      '$coordinate/forge-$coordinate-installer.jar';
}

class ForgeVersions {
  static Future<List<ForgeBuild>> load(String minecraft) async {
    List<ForgeBuild> builds;
    try {
      final response = await DioClient().dio.get(
        'https://bmclapi2.bangbang93.com/forge/minecraft/$minecraft',
      );
      builds = (response.data as List)
          .where(
            (item) => (item['files'] as List? ?? []).any(
              (file) =>
                  file['category'] == 'installer' && file['format'] == 'jar',
            ),
          )
          .map((item) {
            final version = item['version'] as String;
            final branch = item['branch'] as String?;
            return ForgeBuild(
              version,
              '$minecraft-$version${branch == null || branch.isEmpty ? '' : '-$branch'}',
            );
          })
          .toList();
    } catch (_) {
      final response = await DioClient().dio.get(
        'https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml',
      );
      builds = RegExp(r'<version>([^<]+)</version>')
          .allMatches(response.data.toString())
          .map((m) => m[1]!)
          .where((v) => v.startsWith('$minecraft-'))
          .map((v) => ForgeBuild(v.substring(minecraft.length + 1), v))
          .toList();
    }
    String? recommended;
    try {
      final response = await DioClient().dio.get(
        'https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json',
      );
      final json = response.data is String
          ? jsonDecode(response.data)
          : response.data;
      recommended = json['promos']['$minecraft-recommended'] as String?;
    } catch (_) {
      /* Recommendations are optional; the build list is still usable. */
    }
    final unique = <String, ForgeBuild>{};
    for (final build in builds) {
      unique[build.coordinate] = ForgeBuild(
        build.version,
        build.coordinate,
        recommended: build.version == recommended,
      );
    }
    return unique.values.toList()
      ..sort((a, b) => compareForgeVersions(b.version, a.version));
  }

  static Future<ForgeBuild> resolve(String minecraft, String forge) async {
    final builds = await load(minecraft);
    for (final build in builds) {
      if (build.version == forge ||
          build.coordinate == forge ||
          build.coordinate == '$minecraft-$forge') {
        return build;
      }
    }
    throw StateError('找不到 Minecraft $minecraft 对应的 Forge $forge 安装器');
  }
}

class ForgeInstaller {
  static final Map<String, Future<void>> _activeDownloads = {};
  ForgeInstaller({
    required this.gamePath,
    required this.name,
    required this.onProgress,
    this.javaExecutable,
    this.instanceDirectory,
    this.checkCancelled = _noCancellation,
    ForgeJsonLoader? jsonLoader,
    ForgeFileDownloader? fileDownloader,
    ForgeChecksumLoader? checksumLoader,
    this.processorRunner,
    this.logStages = true,
  }) : jsonLoader = jsonLoader ?? jsonUrl,
       fileDownloader = fileDownloader ?? download,
       checksumLoader = checksumLoader ?? installerChecksum;
  final String? javaExecutable;
  final String? instanceDirectory;
  final void Function() checkCancelled;
  final ForgeJsonLoader jsonLoader;
  final ForgeFileDownloader fileDownloader;
  final ForgeChecksumLoader checksumLoader;
  final ForgeProcessorRunner? processorRunner;
  final bool logStages;
  final String gamePath;
  final String name;
  final ForgeProgress onProgress;
  String get instancePath =>
      instanceDirectory ?? safeChild(p.join(gamePath, 'versions'), name);
  String get librariesPath => p.join(gamePath, 'libraries');

  static String mirror(String url) => url
      .replaceFirst(
        'https://maven.minecraftforge.net/',
        'https://bmclapi2.bangbang93.com/maven/',
      )
      .replaceFirst(
        'https://files.minecraftforge.net/maven/',
        'https://bmclapi2.bangbang93.com/maven/',
      )
      .replaceFirst(
        'https://libraries.minecraft.net/',
        'https://bmclapi2.bangbang93.com/maven/',
      )
      .replaceFirst(
        'https://resources.download.minecraft.net/',
        'https://bmclapi2.bangbang93.com/assets/',
      )
      .replaceFirst(
        'https://piston-meta.mojang.com/',
        'https://bmclapi2.bangbang93.com/',
      )
      .replaceFirst(
        'https://piston-data.mojang.com/',
        'https://bmclapi2.bangbang93.com/',
      )
      .replaceFirst(
        'https://launcher.mojang.com/',
        'https://bmclapi2.bangbang93.com/',
      );

  static Future<bool> validFile(
    String path, {
    String? hash,
    String? sha512Hash,
    int? size,
  }) => DownloadUtils.validFile(path, sha1Hash: hash, sha512Hash: sha512Hash);

  static Future<void> download(
    String url,
    String path, {
    String? hash,
    String? sha512Hash,
    int? size,
    List<String> fallbackUrls = const [],
    void Function(double)? progress,
  }) async {
    final pending = _activeDownloads[path];
    if (pending != null) await pending;
    if (await validFile(path, hash: hash, sha512Hash: sha512Hash)) return;
    final raced = _activeDownloads[path];
    if (raced != null) return raced;
    final sources = {
      for (final source in [url, ...fallbackUrls]) ...[mirror(source), source],
    }.toList();
    final task = DownloadUtils.downloadFile(
      url: sources.first,
      fallbackUrls: sources.skip(1).toList(),
      savePath: path,
      sha1Hash: hash,
      sha512Hash: sha512Hash,
      onProgress: progress,
    ).then<void>((_) {});
    _activeDownloads[path] = task;
    try {
      await task;
    } finally {
      _activeDownloads.remove(path);
    }
  }

  static Future<Map<String, dynamic>> jsonUrl(String url) async {
    Object? error;
    for (final source in {mirror(url), url}) {
      try {
        final response = await DioClient().dio.get(source);
        return Map<String, dynamic>.from(
          response.data is String ? jsonDecode(response.data) : response.data,
        );
      } catch (e) {
        error = e;
      }
    }
    throw StateError('获取版本信息失败: $error');
  }

  static Future<String> installerChecksum(String url) async {
    // 直接向发布方读取可执行文件的校验值, 镜像下载也使用该值.
    final response = await DioClient().dio.get(
      '$url.sha1',
      options: Options(responseType: ResponseType.plain),
    );
    final hash = RegExp(r'\b[0-9a-fA-F]{40}\b')
        .firstMatch(response.data.toString())?[0];
    if (hash == null) throw const FormatException('安装器或运行库校验值无效');
    return hash.toLowerCase();
  }

  static Future<void> parallel<T>(
    List<T> items,
    Future<void> Function(T) action, {
    void Function(double)? progress,
    int concurrency = 8,
  }) async {
    var next = 0;
    var completed = 0;
    Object? failure;
    await Future.wait(
      List.generate(items.length < concurrency ? items.length : concurrency, (
        _,
      ) async {
        while (next < items.length && failure == null) {
          final item = items[next++];
          try {
            await action(item);
            progress?.call(++completed / items.length);
          } catch (e) {
            failure ??= e;
          }
        }
      }),
    );
    if (failure != null) throw failure!;
  }

  Future<Map<String, dynamic>> _json(String url) async {
    checkCancelled();
    final result = await jsonLoader(url);
    checkCancelled();
    return result;
  }

  Future<void> _download(
    String url,
    String path, {
    String? hash,
    String? sha512Hash,
    int? size,
    List<String> fallbackUrls = const [],
    void Function(double)? progress,
  }) async {
    checkCancelled();
    await fileDownloader(
      url,
      path,
      hash: hash,
      sha512Hash: sha512Hash,
      size: size,
      fallbackUrls: fallbackUrls,
      progress: progress,
    );
    checkCancelled();
  }

  Future<void> stage(String title, Future<void> Function() action) async {
    checkCancelled();
    onProgress(title, null);
    if (logStages) await LogUtil.log('运行时安装: $title');
    await action();
    checkCancelled();
    onProgress(title, 1);
  }

  Future<void> install({
    required String minecraft,
    required ForgeBuild build,
    String? versionUrl,
  }) async {
    final vanilla = await installVanilla(
      minecraft: minecraft,
      versionUrl: versionUrl,
    );
    await installLoader(
      minecraft: minecraft,
      vanilla: vanilla,
      installerUrl: build.installerUrl,
      expectedCoordinate: 'net.minecraftforge:forge:${build.coordinate}',
    );
  }

  Future<Map<String, dynamic>> installVanilla({
    required String minecraft,
    String? versionUrl,
    void Function(Map<String, dynamic>)? validateMetadata,
  }) async {
    if (instanceNameError(name) case final String error) {
      throw FormatException(error);
    }
    await Directory(instancePath).create(recursive: true);
    late Map<String, dynamic> vanilla;
    await stage('正在读取游戏版本', () async {
      if (versionUrl == null) {
        final manifest = await _json(
          'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json',
        );
        final entry = (manifest['versions'] as List)
            .cast<Map>()
            .where((v) => v['id'] == minecraft)
            .firstOrNull;
        if (entry == null) throw StateError('找不到 Minecraft $minecraft');
        versionUrl = entry['url'] as String;
      }
      vanilla = await _json(versionUrl!);
      if (vanilla['id'] != minecraft) throw StateError('Minecraft 版本信息不匹配');
      validateMetadata?.call(vanilla);
      await File(p.join(instancePath, '$name.json'))
          .writeAsString(jsonEncode(vanilla));
    });
    await installMetadata(vanilla);
    return vanilla;
  }

  /// 安装已经解析的客户端元数据, MMC 自定义组件复用相同校验和下载流程.
  Future<void> installMetadata(Map<String, dynamic> vanilla) async {
    await Directory(instancePath).create(recursive: true);
    await File(p.join(instancePath, '$name.json'))
        .writeAsString(jsonEncode(vanilla));
    await stage('正在下载客户端', () async {
      final client = vanilla['downloads']['client'] as Map;
      await _download(
        client['url'],
        p.join(instancePath, '$name.jar'),
        hash: client['sha1'],
        size: client['size'],
        progress: (v) => onProgress('正在下载客户端', v),
      );
    });
    await stage(
      '正在下载游戏运行库',
      () => downloadLibraries(
        (vanilla['libraries'] as List).cast<Map>(),
        '正在下载游戏运行库',
      ),
    );
    await stage('正在下载游戏资源', () => _assets(vanilla));
    final logging = vanilla['logging']?['client']?['file'] as Map?;
    if (logging != null) {
      await stage(
        '正在下载日志配置',
        () => _download(
          logging['url'],
          safeChild(p.join(gamePath, 'assets', 'log_configs'), logging['id']),
          hash: logging['sha1'],
          size: logging['size'],
        ),
      );
    }
    await stage('正在提取本地运行库', () => _natives(vanilla));
  }

  Future<void> installLoader({
    required String minecraft,
    required Map<String, dynamic> vanilla,
    required String installerUrl,
    String loaderName = 'Forge',
    String? expectedCoordinate,
  }) async {
    checkCancelled();
    final java =
        javaExecutable ??
        await configuredJavaExecutable(await AppConfig.getInstance());
    late Archive archive;
    late Map<String, dynamic> profile;
    late Map<String, dynamic> forge;
    final installerPath = p.join(
      instancePath,
      '${loaderName.toLowerCase()}-installer.jar',
    );
    await stage('正在下载 $loaderName 安装器', () async {
      await _download(
        installerUrl,
        installerPath,
        hash: await checksumLoader(installerUrl),
        progress: (v) => onProgress('正在下载 $loaderName 安装器', v),
      );
      archive = ZipDecoder().decodeBytes(
        await File(installerPath).readAsBytes(),
      );
      profile = archiveJson(archive, 'install_profile.json');
      forge = installerVersion(archive, profile);
      final inherited =
          forge['inheritsFrom'] ??
          profile['minecraft'] ??
          profile['install']?['minecraft'];
      if (inherited != minecraft) {
        throw StateError('$loaderName 安装器与 Minecraft 版本不匹配');
      }
      if (expectedCoordinate != null) {
        final expected = expectedCoordinate.split(':');
        final declared = <String>[
          if (profile['path'] is String) profile['path'] as String,
          if (profile['install']?['path'] is String)
            profile['install']['path'] as String,
          for (final lib in [
            ...?profile['libraries'] as List?,
            ...?forge['libraries'] as List?,
          ])
            if (lib['name'] is String) lib['name'] as String,
        ];
        if (!declared.any((coordinate) {
          final parts = coordinate.split('@').first.split(':');
          return parts.length >= 3 &&
              parts[0] == expected[0] &&
              parts[1] == expected[1] &&
              parts[2] == expected[2];
        })) {
          throw StateError('$loaderName 安装器与请求的加载器版本不匹配');
        }
      }
    });
    await stage('正在下载 $loaderName 运行库', () async {
      for (final file in archive.files.where(
        (f) => f.isFile && !f.isSymbolicLink && f.name.startsWith('maven/'),
      )) {
        checkCancelled();
        final output = File(safeChild(librariesPath, file.name.substring(6)));
        await output.parent.create(recursive: true);
        await output.writeAsBytes(file.content);
      }
      final legacy = profile['install'] as Map?;
      if (legacy != null &&
          legacy['filePath'] != null &&
          legacy['path'] != null) {
        final file = archive.findFile(legacy['filePath']);
        if (file == null) throw StateError('安装器缺少 $loaderName 核心文件');
        final output = File(
          safeChild(librariesPath, mavenPath(legacy['path'])),
        );
        await output.parent.create(recursive: true);
        await output.writeAsBytes(file.content);
      }
      await downloadLibraries(
        [
          ...?profile['libraries'] as List?,
          ...?forge['libraries'] as List?,
        ].cast<Map>(),
        '正在下载 $loaderName 运行库',
      );
    });
    await stage(
      '正在安装 $loaderName',
      () => runProcessors(
        profile,
        archive,
        java,
        installerPath,
        vanilla,
        loaderName: loaderName,
      ),
    );
    await stage('正在检查 $loaderName 安装结果', () async {
      if (forge['mainClass'] is! String) {
        throw StateError('$loaderName 配置缺少启动主类');
      }
      for (final lib in mergedLibraries(vanilla, forge)) {
        if (!rulesAllow(lib['rules'])) continue;
        final artifact = libraryArtifact(lib);
        if (artifact == null) continue;
        if (!await validFile(
          safeChild(librariesPath, artifact['path']),
          hash: artifact['sha1'],
        )) {
          throw StateError('$loaderName 安装后缺少或损坏的运行库: ${lib['name']}');
        }
      }
      await File(p.join(instancePath, '$loaderName.json'))
          .writeAsString(jsonEncode(forge));
    });
  }

  static Map<String, dynamic> archiveJson(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null) throw FormatException('安装包缺少 $path');
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(file.content)));
  }

  static Map<String, dynamic> installerVersion(Archive archive, Map profile) =>
      profile['versionInfo'] is Map
      ? Map<String, dynamic>.from(profile['versionInfo'])
      : archiveJson(
          archive,
          (profile['json'] as String? ?? 'version.json').replaceFirst(
            RegExp(r'^/'),
            '',
          ),
        );

  Future<void> downloadLibraries(List<Map> libraries, String title) async {
    final artifacts = <String, Map>{};
    for (final lib in libraries) {
      if (!rulesAllow(lib['rules']) || lib['clientreq'] == false) continue;
      final artifact = libraryArtifact(lib);
      if (artifact != null) artifacts[artifact['path']] = artifact;
      checkCancelled();
      final native = (lib['natives'] as Map?)?[minecraftOS()] as String?;
      if (native != null) {
        final classifier = native.replaceAll(
          r'${arch}',
          Platform.version.contains('ia32') ? '32' : '64',
        );
        final entry = lib['downloads']?['classifiers']?[classifier];
        if (entry is Map) artifacts[entry['path']] = entry;
      }
    }
    await parallel(artifacts.values.toList(), (artifact) async {
      final url = artifact['url'] as String? ?? '';
      // 空 URL 表示文件由安装器内嵌或由处理器生成.
      if (url.isEmpty) return;
      await _download(
        url,
        safeChild(librariesPath, artifact['path']),
        hash: artifact['sha1'],
        size: artifact['size'],
      );
    }, progress: (v) => onProgress(title, v));
  }

  Future<void> _assets(Map vanilla) async {
    final info = vanilla['assetIndex'] as Map;
    final path = safeChild(
      p.join(gamePath, 'assets', 'indexes'),
      '${info['id']}.json',
    );
    await _download(info['url'], path, hash: info['sha1'], size: info['size']);
    final index = jsonDecode(await File(path).readAsString()) as Map;
    final objects = (index['objects'] as Map).entries.toList();
    await parallel(
      objects,
      (entry) async {
        final hash = entry.value['hash'] as String;
        final objectPath = safeChild(
          p.join(gamePath, 'assets', 'objects'),
          '${hash.substring(0, 2)}/$hash',
        );
        await _download(
          'https://resources.download.minecraft.net/${hash.substring(0, 2)}/$hash',
          objectPath,
          hash: hash,
          size: entry.value['size'],
        );
        if (index['virtual'] == true) {
          final target = File(
            safeChild(
              p.join(gamePath, 'assets', 'virtual', info['id']),
              entry.key,
            ),
          );
          await target.parent.create(recursive: true);
          await File(objectPath).copy(target.path);
        }
        if (index['map_to_resources'] == true) {
          final target = File(
            safeChild(p.join(instancePath, 'resources'), entry.key),
          );
          await target.parent.create(recursive: true);
          if (instanceDirectory != null &&
              await target.exists() &&
              !await validFile(target.path, hash: hash)) {
            throw FormatException('整合包文件与游戏资源冲突: ${entry.key}');
          }
          await File(objectPath).copy(target.path);
        }
      },
      progress: (v) => onProgress('正在下载游戏资源', v),
      concurrency: 32,
    );
  }

  Future<void> _natives(Map vanilla) async {
    final target = p.join(instancePath, 'natives');
    await Directory(target).create(recursive: true);
    for (final lib in vanilla['libraries'] as List) {
      if (!rulesAllow(lib['rules'])) continue;
      checkCancelled();
      final native = (lib['natives'] as Map?)?[minecraftOS()] as String?;
      if (native == null) continue;
      final classifier = native.replaceAll(
        r'${arch}',
        Platform.version.contains('ia32') ? '32' : '64',
      );
      final artifact = lib['downloads']?['classifiers']?[classifier];
      if (artifact == null) throw StateError('缺少本地运行库: ${lib['name']}');
      final archive = ZipDecoder().decodeBytes(
        await File(safeChild(librariesPath, artifact['path'])).readAsBytes(),
      );
      final excludes = (lib['extract']?['exclude'] as List? ?? ['META-INF/'])
          .cast<String>();
      for (final file in archive.files.where(
        (f) => f.isFile && !f.isSymbolicLink,
      )) {
        if (excludes.any((prefix) => file.name.startsWith(prefix))) continue;
        final output = File(safeChild(target, file.name));
        await output.parent.create(recursive: true);
        await output.writeAsBytes(file.content);
      }
    }
  }

  Future<void> runProcessors(
    Map profile,
    Archive archive,
    String java,
    String installer,
    Map vanilla, {
    String loaderName = 'Forge',
  }) async {
    final temp = await Directory(instancePath).createTemp('.forge-processors-');
    try {
      final data = <String, String>{
        'SIDE': 'client',
        'ROOT': gamePath,
        'INSTALLER': installer,
        'LIBRARY_DIR': librariesPath,
        'MINECRAFT_VERSION': vanilla['id'],
        'MINECRAFT_JAR': p.join(instancePath, '$name.jar'),
      };
      for (final entry in (profile['data'] as Map? ?? {}).entries) {
        checkCancelled();
        final value = entry.value['client'] as String?;
        if (value == null) continue;
        if (value.startsWith('[') || value.startsWith("'")) {
          data[entry.key] = resolveProcessorValue(value, data, librariesPath);
        } else {
          final path = value.replaceFirst(RegExp(r'^/'), '');
          final file = archive.findFile(path);
          if (file == null) throw StateError('安装器缺少数据文件: $path');
          final output = File(safeChild(temp.path, path));
          await output.parent.create(recursive: true);
          await output.writeAsBytes(file.content);
          data[entry.key] = output.path;
        }
      }
      final processors = (profile['processors'] as List? ?? [])
          .cast<Map>()
          .where(
            (v) =>
                v['sides'] == null || (v['sides'] as List).contains('client'),
          )
          .toList();
      for (var i = 0; i < processors.length; i++) {
        checkCancelled();
        final processor = processors[i];
        String resolve(String value) =>
            resolveProcessorValue(value, data, librariesPath);
        final outputs = <String, String>{
          for (final entry in (processor['outputs'] as Map? ?? {}).entries)
            resolve(entry.key): resolve(entry.value),
        };
        var complete = outputs.isNotEmpty;
        for (final entry in outputs.entries) {
          if (!await validFile(entry.key, hash: entry.value)) complete = false;
        }
        if (!complete) {
          final args = (processor['args'] as List? ?? [])
              .cast<String>()
              .map(resolve)
              .toList();
          // 单独下载映射文件, 确保镜像回退和哈希校验同样生效.
          if (args.contains('DOWNLOAD_MOJMAPS') &&
              vanilla['downloads']?['client_mappings'] != null) {
            final mapping = vanilla['downloads']['client_mappings'];
            final output = args[args.indexOf('--output') + 1];
            await _download(
              mapping['url'],
              output,
              hash: mapping['sha1'],
              size: mapping['size'],
            );
          } else {
            final jar = safeChild(librariesPath, mavenPath(processor['jar']));
            final processorArchive = ZipDecoder().decodeBytes(
              await File(jar).readAsBytes(),
            );
            final manifest = processorArchive.findFile('META-INF/MANIFEST.MF');
            if (manifest == null) {
              throw StateError('安装处理器缺少 MANIFEST: ${processor['jar']}');
            }
            final text = utf8
                .decode(manifest.content)
                .replaceAll(RegExp(r'\r?\n '), '');
            final main = RegExp(
              r'^Main-Class:\s*(.+)',
              multiLine: true,
            ).firstMatch(text)?[1]?.trim();
            if (main == null) {
              throw StateError('安装处理器缺少 Main-Class: ${processor['jar']}');
            }
            final cp = [
              jar,
              ...(processor['classpath'] as List? ?? []).map(
                (v) => safeChild(librariesPath, mavenPath(v)),
              ),
            ];
            await _processor(java, [
              '-cp',
              cp.join(Platform.isWindows ? ';' : ':'),
              main,
              ...args,
            ], loaderName: loaderName);
          }
          for (final entry in outputs.entries) {
            if (!await validFile(entry.key, hash: entry.value)) {
              throw StateError('安装处理结果校验失败: ${p.basename(entry.key)}');
            }
          }
        }
        checkCancelled();
        onProgress('正在安装 $loaderName', (i + 1) / processors.length);
      }
      // 新安装器可能省略 outputs 和 SHA, 仍需检查声明的补丁客户端和拆分 JAR 非空.
      for (final key in ['PATCHED', 'MC_SLIM', 'MC_EXTRA']) {
        if (data[key] != null &&
            !await validFile(data[key]!, hash: data['${key}_SHA'])) {
          throw StateError('$loaderName 生成文件校验失败: $key');
        }
      }
    } finally {
      await temp.delete(recursive: true);
    }
  }

  Future<void> _processor(
    String java,
    List<String> args, {
    String loaderName = 'Forge',
  }) async {
    if (processorRunner != null) {
      await processorRunner!(java, args, instancePath);
      return;
    }
    final process = await Process.start(
      java,
      args,
      workingDirectory: instancePath,
    );
    final log = File(p.join(instancePath, 'forge-install.log'))
        .openWrite(mode: FileMode.append);
    final stdout = process.stdout.forEach(log.add);
    final stderr = process.stderr.forEach(log.add);
    try {
      final code = await process.exitCode.timeout(
        const Duration(minutes: 15),
        onTimeout: () {
          process.kill();
          throw StateError('$loaderName 安装处理器超时');
        },
      );
      await Future.wait([stdout, stderr]);
      if (code != 0) {
        throw StateError(
          '$loaderName 安装失败 (退出码 $code), 详见版本目录内 forge-install.log',
        );
      }
    } finally {
      await Future.wait([stdout, stderr]);
      await log.close();
    }
  }
}
