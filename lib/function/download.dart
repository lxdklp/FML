import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:fml/constants.dart';
import 'dart:io';
import 'dart:async';
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

// 进度更新
class _ProgressUpdater {
  final Function(double progress)? onProgress;
  final int totalTasks;
  final Duration throttleDuration = const Duration(milliseconds: 100);
  double _lastReportedProgress = 0.0;
  int _successCount = 0;
  DateTime _lastUpdateTime = DateTime.now();
  Timer? _pendingTimer;

  _ProgressUpdater({this.onProgress, required this.totalTasks});

  // 增加成功计数
  Future<void> incrementSuccess() async {
    _successCount++;
    await _scheduleUpdate();
  }

  // 调度进度更新
  Future<void> _scheduleUpdate() async {
    if (onProgress == null || totalTasks == 0) return;
    final now = DateTime.now();
    final elapsed = now.difference(_lastUpdateTime);
    if (elapsed >= throttleDuration) {
      await _doUpdate();
    } else {
      _pendingTimer?.cancel();
      _pendingTimer = Timer(throttleDuration - elapsed, _doUpdate);
    }
  }

  // 执行进度更新
  Future<void> _doUpdate() async {
    if (onProgress == null || totalTasks == 0) return;
    final newProgress = _successCount / totalTasks;
    if (newProgress > _lastReportedProgress) {
      _lastReportedProgress = newProgress;
      _lastUpdateTime = DateTime.now();
      onProgress!(newProgress);
    }
  }

  // 强制刷新最终进度
  void flush() {
    _pendingTimer?.cancel();
    _doUpdate();
  }

  int get successCount => _successCount;
}

class DownloadUtils {
  static const int _maxRetries = 5;
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
      return gAppUserAgent;
    } else {
      return 'lxdklp/$gAppUserAgent (fml.lxdklp.top)';
    }
  }

  /// 下载单个文件
  /// [url] 下载地址
  /// [savePath] 保存路径
  /// [onProgress] 下载进度回调
  /// [onSuccess] 下载成功回调
  /// [onError] 下载失败回调
  /// [onCancel] 下载取消回调
  static Future<CancelToken> downloadFile({
    required String url,
    required String savePath,
    Function(double progress)? onProgress,
    VoidCallback? onSuccess,
    Function(String error)? onError,
    VoidCallback? onCancel,
  }) async {
    final dio = await _getSharedDio();
    final CancelToken cancelToken = CancelToken();
    final userAgent = _getUserAgent(url);
    const int maxRetries = 5;
    for (int retry = 0; retry <= maxRetries; retry++) {
      try {
        final directory = Directory(
          savePath.substring(0, savePath.lastIndexOf(Platform.pathSeparator)),
        );
        if (!directory.existsSync()) {
          directory.createSync(recursive: true);
        }
        final options = Options(
          headers: {'User-Agent': userAgent},
          responseType: ResponseType.stream,
        );
        await dio.download(
          url,
          savePath,
          options: options,
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            if (total != -1) {
              final progress = received / total;
              onProgress?.call(progress);
            }
          },
        );
        onSuccess?.call();
        return cancelToken;
      } catch (e) {
        if (e is DioException && CancelToken.isCancel(e)) {
          onCancel?.call();
          return cancelToken;
        }
        if (retry >= maxRetries) {
          onError?.call(e.toString());
          return cancelToken;
        }
        final delayMs = (300 * (1 << retry)).clamp(300, 30000);
        await LogUtil.log(
          '下载失败 (第 ${retry + 1} 次): $url - $e —— ${delayMs}ms 后重试',
          level: 'WARNING',
        );
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
    return cancelToken;
  }

  /// 批量下载文件
  /// [tasks] 下载任务列表
  /// [onProgress] 进度回调 (0.0 ~ 1.0)
  /// [fileType] 文件类型描述
  static Future<DownloadResult> batchDownload({
    required List<Map<String, String>> tasks,
    Function(double progress)? onProgress,
    String fileType = '文件',
  }) async {
    if (tasks.isEmpty) {
      await LogUtil.log('$fileType列表为空,无需下载', level: 'INFO');
      return DownloadResult(
        failedList: [],
        success: true,
        totalCount: 0,
        completedCount: 0,
      );
    }
    List<Map<String, String>> currentTasks = List.from(tasks);
    List<Map<String, String>> failedList = [];
    int currentRetryCount = 0;
    final int totalTasks = tasks.length;
    final progressUpdater = _ProgressUpdater(
      onProgress: onProgress,
      totalTasks: totalTasks,
    );
    while (currentTasks.isNotEmpty && currentRetryCount <= _maxRetries) {
      if (currentRetryCount > 0) {
        await LogUtil.log(
          '准备重试下载 ${currentTasks.length} 个失败的$fileType (第 $currentRetryCount 次重试)',
          level: 'INFO',
        );
      }
      await LogUtil.log(
        '开始下载${currentTasks.length}个$fileType,并发数 $_concurrentDownloads',
        level: 'INFO',
      );
      failedList = await _workerPoolDownload(
        tasks: currentTasks,
        fileType: fileType,
        progressUpdater: progressUpdater,
      );
      if (failedList.isEmpty) {
        break;
      }
      currentTasks = List.from(failedList);
      currentRetryCount++;
    }
    // 单线程无限重试剩余失败任务
    if (failedList.isNotEmpty) {
      await LogUtil.log(
        '已达最大并发重试次数，开始单线程重试 ${failedList.length} 个$fileType',
        level: 'WARNING',
      );
      failedList = await _singleThreadRetryDownload(
        failedList: failedList,
        fileType: fileType,
        progressUpdater: progressUpdater,
      );
    }
    progressUpdater.flush();
    return DownloadResult(
      failedList: failedList,
      success: failedList.isEmpty,
      totalCount: totalTasks,
      completedCount: progressUpdater.successCount,
    );
  }

  static Future<List<Map<String, String>>> _workerPoolDownload({
    required List<Map<String, String>> tasks,
    required String fileType,
    required _ProgressUpdater progressUpdater,
  }) async {
    final int currentBatchSize = tasks.length;
    int taskIndex = 0;
    int processedCount = 0;
    final List<Map<String, String>> failedList = [];
    // 工作线程
    Future<void> worker(int workerId) async {
      while (true) {
        if (taskIndex >= tasks.length) break;
        final currentTaskIndex = taskIndex++;
        final task = tasks[currentTaskIndex];
        try {
          bool downloadSuccess = false;
          await downloadFile(
            url: task['url']!,
            savePath: task['path']!,
            onProgress: (_) {},
            onSuccess: () {
              downloadSuccess = true;
            },
            onError: (error) {},
          );
          processedCount++;
          if (downloadSuccess) {
            progressUpdater.incrementSuccess();
          } else {
            failedList.add(task);
          }
        } catch (e) {
          processedCount++;
          failedList.add(task);
        }
      }
    }

    final workers = List.generate(
      _concurrentDownloads.clamp(1, currentBatchSize),
      (index) => worker(index),
    );
    await Future.wait(workers);
    await LogUtil.log(
      '批次完成: 处理 $processedCount/$currentBatchSize, 失败: ${failedList.length}',
      level: 'INFO',
    );
    return failedList;
  }

  // 单线程无限重试下载
  static Future<List<Map<String, String>>> _singleThreadRetryDownload({
    required List<Map<String, String>> failedList,
    required String fileType,
    required _ProgressUpdater progressUpdater,
  }) async {
    List<Map<String, String>> currentFailedList = List.from(failedList);
    while (currentFailedList.isNotEmpty) {
      List<Map<String, String>> nextRetryList = [];
      for (var task in currentFailedList) {
        bool success = false;
        while (!success) {
          try {
            bool downloadComplete = false;
            await downloadFile(
              url: task['url']!,
              savePath: task['path']!,
              onProgress: (_) {},
              onSuccess: () {
                downloadComplete = true;
              },
              onError: (error) {},
            );
            if (downloadComplete) {
              success = true;
              progressUpdater.incrementSuccess();
            } else {
              await Future.delayed(Duration(milliseconds: 500));
            }
          } catch (e) {
            await Future.delayed(Duration(seconds: 1));
          }
        }
      }
      currentFailedList = nextRetryList;
    }
    await LogUtil.log('所有$fileType已成功下载', level: 'INFO');
    return [];
  }
}
