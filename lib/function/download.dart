import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class DownloadUtils {
  /// [url] 下载地址
  /// [savePath] 保存路径
  /// [onProgress] 下载进度回调
  /// [onSuccess] 下载成功回调
  /// [onError] 下载失败回调
  /// [onCancel] 下载取消回调
  /// CancelToken 用于取消下载
  static Future<CancelToken> downloadFile({
    required String url,
    required String savePath,
    Function(double progress)? onProgress,
    VoidCallback? onSuccess,
    Function(String error)? onError,
    VoidCallback? onCancel,
  }) async {
    final Dio dio = Dio();
    final CancelToken cancelToken = CancelToken();
    final prefs = await SharedPreferences.getInstance();
    final appVersion = prefs.getString('version') ?? 'unknown';
    final userAgent = 'FML/$appVersion';
    try {
      // 创建目录
      final directory = Directory(savePath.substring(0, savePath.lastIndexOf(Platform.pathSeparator)));
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      // BMCLAPI要求User-Agent
      final options = Options(
        headers: {
          'User-Agent': userAgent,
        },
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
      }
      catch (e) {
        if (e is DioException && CancelToken.isCancel(e)) {
          onCancel?.call();
        } else {
          onError?.call(e.toString());
        }
    }
    return cancelToken;
  }
}