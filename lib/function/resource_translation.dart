import 'package:dio/dio.dart';

class ResourceTranslationException implements Exception {
  const ResourceTranslationException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<String> translateResourceDetails({
  required Dio dio,
  required String text,
  required String client,
  required String userAgent,
  required CancelToken cancelToken,
  bool direct = false,
}) async {
  final endpoint = direct
      ? 'https://translate.googleapis.com/translate_a/single'
      : 'https://translate.lxdklp.top/translate_a/single';
  final service = direct ? 'Google 翻译' : '翻译代理';
  if (cancelToken.isCancelled) throw cancelToken.cancelError!;
  for (var attempt = 0; attempt < 2; attempt++) {
    if (attempt > 0) {
      await Future.any([
        Future<void>.delayed(const Duration(milliseconds: 600)),
        cancelToken.whenCancel.then<void>((error) => throw error),
      ]);
    }
    if (cancelToken.isCancelled) throw cancelToken.cancelError!;

    try {
      final response = await dio.get<dynamic>(
        endpoint,
        queryParameters: {
          'client': client,
          'sl': 'auto',
          'tl': 'zh-CN',
          'dt': 't',
          'q': text,
        },
        options: Options(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 40),
          headers: {'User-Agent': userAgent},
          validateStatus: (status) => status != null,
        ),
        cancelToken: cancelToken,
      );
      final data = response.data;
      final code = data is Map ? data['code'] : null;
      final upstreamStatus = data is Map ? data['upstream_status'] : null;
      // 不重试未知的 code=1、限流或参数错误, 避免重复施压。
      const transientStatuses = {502, 503, 504};
      if (attempt == 0 &&
          (transientStatuses.contains(response.statusCode) ||
              transientStatuses.contains(upstreamStatus))) {
        continue;
      }
      if (response.statusCode != 200 ||
          (!direct && (data is! Map || code != 0))) {
        final message = data is Map ? data['msg'] : null;
        final detail = message is String && message.trim().isNotEmpty
            ? '：${message.length > 160 ? message.substring(0, 160) : message}'
            : '';
        throw ResourceTranslationException(
          '$service 返回错误(HTTP ${response.statusCode}'
          '${direct ? '' : ', code=$code'})$detail',
        );
      }
      final Object? translated;
      if (direct) {
        final segments = data is List && data.isNotEmpty ? data.first : null;
        if (segments is! List ||
            segments.isEmpty ||
            segments.any(
              (segment) =>
                  segment is! List ||
                  segment.isEmpty ||
                  segment.first is! String,
            )) {
          throw const ResourceTranslationException('Google 翻译响应格式异常');
        }
        translated = segments.map((segment) => segment[0] as String).join();
      } else {
        translated = data is Map ? data['text'] : null;
      }
      if (translated is! String || translated.trim().isEmpty) {
        throw const ResourceTranslationException('翻译服务未返回有效译文');
      }
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      return translated;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      const transientErrors = {
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      };
      if (attempt == 0 && transientErrors.contains(e.type)) continue;
      final message = switch (e.type) {
        DioExceptionType.connectionTimeout => '连接$service超时, 重试后仍未能建立连接',
        DioExceptionType.receiveTimeout => '等待$service响应超时, 重试后仍未收到完整响应',
        DioExceptionType.sendTimeout => '发送翻译请求超时, 重试后仍未完成',
        DioExceptionType.connectionError => '无法连接$service, 重试后仍失败, 请检查网络',
        DioExceptionType.badCertificate => '$service的 TLS 证书验证失败',
        _ => '翻译请求失败(${e.type.name}), 请稍后重试',
      };
      throw ResourceTranslationException(message);
    }
  }
  throw const ResourceTranslationException('翻译请求重试后仍失败');
}
