import 'dart:async';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;

import 'dio_client.dart';

typedef _JavaVersion = ({int major, int minor, int patch});

class ChunkbaseVersions {
  ChunkbaseVersions(this._dio);

  static final shared = ChunkbaseVersions(DioClient().dio);
  static final mapUrl = Uri.https('www.chunkbase.com', '/apps/biome-finder');
  static const _cacheDuration = Duration(minutes: 5);
  static const _timeout = Duration(seconds: 4);
  static final _releasePattern = RegExp(r'^(\d+)\.(\d+)(?:\.(\d+))?$');
  static final _platformPattern = RegExp(
    r'^(?:java//)?(java_(\d+(?:_\d+){1,2}))$',
  );

  final Dio _dio;
  Map<_JavaVersion, String> _platforms = const {};
  DateTime? _loadedAt;
  Future<void>? _refresh;

  Future<String?> platformFor(String? gameVersion) async {
    final version = _parseVersion(gameVersion ?? '');
    if (version == null) return null;

    final loadedAt = _loadedAt;
    if (loadedAt == null ||
        DateTime.now().difference(loadedAt) >= _cacheDuration) {
      await (_refresh ??= _loadPlatforms().whenComplete(() => _refresh = null));
    }

    // 同一个 Minecraft 版本系列取不高于存档版本的最近分组.
    String? platform;
    var latestPatch = -1;
    for (final entry in _platforms.entries) {
      final group = entry.key;
      if (group.major == version.major &&
          group.minor == version.minor &&
          group.patch <= version.patch &&
          group.patch > latestPatch) {
        latestPatch = group.patch;
        platform = entry.value;
      }
    }
    return platform;
  }

  Future<void> _loadPlatforms() async {
    final token = CancelToken();
    try {
      final response = await _dio
          .getUri<String>(
            mapUrl,
            cancelToken: token,
            options: Options(responseType: ResponseType.plain),
          )
          .timeout(_timeout);

      final document = html.parse(response.data ?? '');
      final platforms = <_JavaVersion, String>{};
      for (final option in document.querySelectorAll('select option[value]')) {
        final match = _platformPattern.firstMatch(option.attributes['value']!);
        if (match == null) continue;
        final version = _parseVersion(match[2]!.replaceAll('_', '.'));
        if (version != null) platforms[version] = match[1]!;
      }
      if (platforms.isNotEmpty) {
        _platforms = platforms;
        _loadedAt = DateTime.now();
      }
    } on TimeoutException {
      token.cancel();
    } on DioException {
      // 请求失败时继续使用最近一次成功读取的版本选项.
    }
  }

  static _JavaVersion? _parseVersion(String value) {
    final match = _releasePattern.firstMatch(value.trim());
    if (match == null) return null;
    final major = int.tryParse(match[1]!);
    final minor = int.tryParse(match[2]!);
    final patch = int.tryParse(match[3] ?? '0');
    if (major == null || minor == null || patch == null) return null;
    return (major: major, minor: minor, patch: patch);
  }
}
