import 'dart:io';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:dio/io.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fml/constants.dart';
import 'package:fml/function/log.dart';

/// 下载任务结果
class DownloadResult {
  final List<Map<String, String>> failedList;
  final bool success;
  final int totalCount;
  final int completedCount;

  DownloadResult({
    required this.failedList,
    required this.success,
    required this.totalCount,
    required this.completedCount,
  });
}

class DownloadUtils {
  static const int maxAttempts = 5;
  static const int _concurrentDownloads = 64;
  static Dio? _sharedDio;

  static Future<Dio> _getSharedDio() async {
    if (_sharedDio == null) {
      _sharedDio = Dio();
      // 配置 HttpClient
      (_sharedDio!.httpClientAdapter as IOHttpClientAdapter).createHttpClient =
          () {
            final client = HttpClient();
            client.maxConnectionsPerHost = _concurrentDownloads;
            client.idleTimeout = const Duration(seconds: 30);
            client.connectionTimeout = const Duration(seconds: 15);
            return client;
          };
      _sharedDio!.options.connectTimeout = const Duration(seconds: 15);
      _sharedDio!.options.receiveTimeout = const Duration(minutes: 5);
      _sharedDio!.options.sendTimeout = const Duration(seconds: 30);
    }
    return _sharedDio!;
  }

  /// 获取对应 URL 的 User-Agent
  static String _getUserAgent(String url) {
    if (url.contains('bmclapi2.bangbang93.com')) {
      return gAppDefaultUserAgent;
    } else {
      return gAppModrinthUserAgent;
    }
  }

  /// 校验哈希
  static Future<bool> validFile(
    String path, {
    String? sha1Hash,
    String? sha512Hash,
  }) async {
    final file = File(path);
    if (!await file.exists()) return false;
    final checks = <Hash, String>{
      if (sha1Hash != null && sha1Hash.isNotEmpty) sha1: sha1Hash,
      if (sha512Hash != null && sha512Hash.isNotEmpty) sha512: sha512Hash,
    };
    if (checks.isEmpty) return await file.length() > 0;
    for (final check in checks.entries) {
      final actual = (await check.key.bind(file.openRead()).first).toString();
      if (actual != check.value.trim().toLowerCase()) return false;
    }
    return true;
  }

  /// 5 次重试上限
  static Future<CancelToken> downloadFile({
    required String url,
    required String savePath,
    Function(double progress)? onProgress,
    VoidCallback? onSuccess,
    Function(String error)? onError,
    VoidCallback? onCancel,
    CancelToken? cancellationToken,
    String? sha1Hash,
    String? sha512Hash,
    List<String> fallbackUrls = const [],
    Duration attemptTimeout = const Duration(minutes: 10),
  }) async {
    final dio = await _getSharedDio();
    final cancelToken = cancellationToken ?? CancelToken();
    final sources = {url, ...fallbackUrls}.toList();
    final temp = '$savePath.part';
    final hasHash =
        (sha1Hash?.isNotEmpty ?? false) || (sha512Hash?.isNotEmpty ?? false);
    if (hasHash &&
        await validFile(savePath, sha1Hash: sha1Hash, sha512Hash: sha512Hash)) {
      onSuccess?.call();
      return cancelToken;
    }
    await Directory(p.dirname(savePath)).create(recursive: true);
    if (hasHash &&
        await validFile(temp, sha1Hash: sha1Hash, sha512Hash: sha512Hash)) {
      await File(temp).rename(savePath);
      onSuccess?.call();
      return cancelToken;
    }
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (cancelToken.isCancelled) {
        onCancel?.call();
        return cancelToken;
      }
      final source = sources[(attempt - 1) % sources.length];
      final attemptToken = CancelToken();
      final finished = Completer<void>();
      unawaited(
        Future.any([cancelToken.whenCancel.then<void>((_) {}), finished.future])
            .then((_) {
              if (cancelToken.isCancelled) attemptToken.cancel('下载已取消');
            }),
      );
      final timeout =
          sources.length > 1 &&
              Uri.parse(source).host == 'bmclapi2.bangbang93.com'
          ? const Duration(seconds: 45)
          : attemptTimeout;
      final timer = Timer(timeout, () => attemptToken.cancel('下载超时'));
      try {
        await dio.download(
          source,
          temp,
          options: Options(
            headers: {'User-Agent': _getUserAgent(source)},
            responseType: ResponseType.stream,
          ),
          cancelToken: attemptToken,
          onReceiveProgress: (received, total) {
            if (total > 0) onProgress?.call(received / total);
          },
        );
        if (hasHash &&
            !await validFile(
              temp,
              sha1Hash: sha1Hash,
              sha512Hash: sha512Hash,
            )) {
          throw StateError('SHA 校验失败');
        }
        await File(temp).rename(savePath);
        onSuccess?.call();
        return cancelToken;
      } catch (e) {
        if (await File(temp).exists()) await File(temp).delete();
        if (cancelToken.isCancelled) {
          onCancel?.call();
          return cancelToken;
        }
        final message =
            '文件 ${p.basename(savePath)} 下载或 SHA 校验失败（第 $attempt/$maxAttempts 次）：$e';
        await LogUtil.log(
          message,
          level: attempt == maxAttempts ? 'ERROR' : 'WARNING',
        );
        if (attempt == maxAttempts) {
          final error = '$message, 已停止重试';
          if (onError != null) {
            onError(error);
            return cancelToken;
          }
          throw StateError(error);
        }
      } finally {
        timer.cancel();
        finished.complete();
      }
      await Future.delayed(Duration(milliseconds: 300 * (1 << (attempt - 1))));
    }
    return cancelToken;
  }

  /// 重试由 downloadFile 负责
  static Future<DownloadResult> batchDownload({
    required List<Map<String, String>> tasks,
    Function(double progress)? onProgress,
    String fileType = '文件',
  }) async {
    final unique = <String, Map<String, String>>{};
    for (final task in tasks) {
      unique.putIfAbsent(task['path']!, () => task);
    }
    final items = unique.values.toList();
    final failed = <Map<String, String>>[];
    var next = 0;
    var completed = 0;
    var lastProgress = DateTime.now();
    String? firstError;
    Future<void> worker() async {
      while (next < items.length && firstError == null) {
        final task = items[next++];
        try {
          await downloadFile(
            url: task['url']!,
            savePath: task['path']!,
            sha1Hash: task['sha1'],
            sha512Hash: task['sha512'],
          );
          completed++;
          final now = DateTime.now();
          if (completed == items.length ||
              now.difference(lastProgress).inMilliseconds >= 100) {
            onProgress?.call(completed / items.length);
            lastProgress = now;
          }
        } catch (e) {
          failed.add(task);
          firstError ??= e.toString();
        }
      }
    }

    await Future.wait(
      List.generate(
        items.length.clamp(0, _concurrentDownloads),
        (_) => worker(),
      ),
    );
    if (firstError != null) throw StateError('$fileType下载失败：$firstError');
    return DownloadResult(
      failedList: failed,
      success: true,
      totalCount: items.length,
      completedCount: completed,
    );
  }
}
