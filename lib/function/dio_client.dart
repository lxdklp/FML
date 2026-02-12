import 'package:dio/dio.dart';
import 'package:fml/function/download.dart';
import 'package:flutter/foundation.dart';

import 'package:fml/constants.dart';

///
/// 一个自带默认配置的Dio单例
///
/// 对于下载调用请使用[DownloadUtils]
///
class DioClient {
  // 静态实例保证 DioClient 只有一个实例
  static final DioClient _instance = DioClient._internal();

  // 公开的Dio实例
  late Dio dio;

  factory DioClient() => _instance;

  DioClient._internal() {
    dio = Dio(
      BaseOptions(
        // 固定超时时长
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );

    ///
    /// 添加拦截器
    ///

    // UA拦截器
    dio.interceptors.add(_getUserAgentInterceptor());

    // 在Debug模式添加日志输出
    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(
          request: false,
          requestHeader: false,
          requestBody: false,
          responseHeader: false,
          error: true,
        ),
      );
    }
  }

  ///
  /// 设置UserAgent
  ///
  InterceptorsWrapper _getUserAgentInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        final existingUserAgent = options.headers['User-Agent'];
        if (existingUserAgent == null ||
            (existingUserAgent is String && existingUserAgent.isEmpty)) {
          //'$kAppNameAbb/${Platform.operatingSystem}/$_appVersion ${kDebugMode ? 'debug' : ''}';
          final userAgent = gAppUserAgent;
          options.headers['User-Agent'] = userAgent;
        }
        return handler.next(options);
      },
    );
  }
}
