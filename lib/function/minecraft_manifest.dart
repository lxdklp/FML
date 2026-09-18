import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fml/function/dio_client.dart';
import 'package:fml/function/log.dart';
import 'package:fml/models/minecraft_version.dart';

class MinecraftManifestException implements Exception {
  const MinecraftManifestException();

  @override
  String toString() => '无法获取完整的游戏版本列表，请检查网络后重试。';
}

// 解析版本清单
List<MinecraftVersion> parseMinecraftManifest(dynamic response) {
  final data = response is String ? jsonDecode(response) : response;
  if (data is! Map ||
      data['versions'] is! List ||
      (data['versions'] as List).isEmpty) {
    throw const FormatException('版本清单缺少有效的 versions 列表');
  }
  return (data['versions'] as List).map((entry) {
    if (entry is! Map ||
        ['id', 'type', 'url', 'time', 'releaseTime'].any(
          (key) => entry[key] is! String || (entry[key] as String).isEmpty,
        )) {
      throw const FormatException('版本清单包含无效的版本条目');
    }
    final uri = Uri.tryParse(entry['url'] as String);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        DateTime.tryParse(entry['time'] as String) == null ||
        DateTime.tryParse(entry['releaseTime'] as String) == null) {
      throw const FormatException('版本清单包含无效的下载地址或日期');
    }
    return MinecraftVersion.fromJson(Map<String, dynamic>.from(entry));
  }).toList();
}

// 请求版本
Future<List<MinecraftVersion>> fetchMinecraftManifest({Dio? client}) async {
  final dio = client ?? DioClient().dio;
  const sources = [
    'https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json',
    'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json',
  ];
  for (final source in sources) {
    try {
      final response = await dio.get<dynamic>(
        source,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 20),
          headers: {'Cache-Control': 'no-cache'},
        ),
      );
      if (response.statusCode != 200) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
        );
      }
      final versions = parseMinecraftManifest(response.data);
      await LogUtil.log('版本清单加载成功: $source，共 ${versions.length} 个版本');
      return versions;
    } catch (error) {
      // Do not include response bodies or FormatException.source: a manifest
      // contains hundreds of KB and is not a useful user-facing error message.
      final reason = error is DioException
          ? '网络请求失败（${error.response?.statusCode ?? error.type.name}）'
          : '版本清单格式不正确或响应不完整';
      await LogUtil.log('版本清单来源不可用: $source，$reason', level: 'WARNING');
    }
  }
  throw const MinecraftManifestException();
}
