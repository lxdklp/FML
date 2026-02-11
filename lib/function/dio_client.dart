import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:fml/constants.dart';
import 'package:package_info_plus/package_info_plus.dart';

///
/// 一个自带默认配置的Dio单例
///
/// TODO: 分离下载任务与常规任务的Dio实例，避免无限等待
///
class DioClient {
  // 静态实例保证 DioClient 只有一个实例
  static final DioClient _instance = DioClient._internal();

  // 公开的Dio实例
  late Dio dio;

  late String _appVersion;

  factory DioClient() => _instance;

  DioClient._internal() {
    // 初始化客户端版本
    _initAppVersion();

    dio = Dio(
      BaseOptions(
        // 固定超时时长
        connectTimeout: const Duration(seconds: 30),
        // 不限制接受超时，避免大文件下载过慢
        receiveTimeout: null,
      ),
    );

    ///
    /// 添加拦截器
    ///

    // UA拦截器
    dio.interceptors.add(_getUserAgentInterceptor());

    // 添加日志输出
    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(
          request: false,
          requestHeader: true,
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
          final userAgent =
              '$kAppNameAbb/${Platform.operatingSystem}/$_appVersion ${kDebugMode ? 'debug' : ''}';
          options.headers['User-Agent'] = userAgent;
        }
        return handler.next(options);
      },
    );
  }

  //
  // 初始化客户端版本
  //
  Future<void> _initAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    _appVersion = packageInfo.version;
  }
}
