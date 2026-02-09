import 'dart:io';
import 'package:fml/function/dio_client.dart';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:fml/function/log.dart';
import 'package:fml/function/download.dart';
import 'package:fml/function/crypto_util.dart';

// 检查authlib-injector
Future<bool> checkAuthlibInjector(String gamePath) async {
  File authlibFile = File(
    '$gamePath${Platform.pathSeparator}authlib-injector.jar',
  );
  if (authlibFile.existsSync()) {
    LogUtil.log('authlib-injector 已存在', level: 'INFO');
    final stream = authlibFile.openRead();
    final hash = await sha256.bind(stream).first;
    final hashString = hash.toString();
    try {
      final response = await DioClient().dio.get(
        'https://bmclapi2.bangbang93.com/mirrors/authlib-injector/artifact/latest.json',
      );
      if (response.statusCode == 200 && response.data.isNotEmpty) {
        final String? expectedHash = response.data['checksums']['sha256'];
        if (expectedHash != null && expectedHash == hashString) {
          LogUtil.log('authlib-injector 校验通过', level: 'INFO');
        } else {
          LogUtil.log('authlib-injector 校验失败，正在重新下载', level: 'WARNING');
          return false;
        }
      } else {
        LogUtil.log('获取 authlib-injector 版本信息失败，无法校验', level: 'WARNING');
        return false;
      }
    } catch (e) {
      LogUtil.log('获取 authlib-injector 版本信息失败: $e', level: 'ERROR');
      return false;
    }
    return true;
  } else {
    return false;
  }
}

// 下载authlib-injector
Future<void> downloadAuthlibInjector(String gamePath) async {
  LogUtil.log('加载authlib-injector版本', level: 'INFO');
  try {
    final response = await DioClient().dio.get(
      'https://bmclapi2.bangbang93.com/mirrors/authlib-injector/artifact/latest.json',
    );
    if (response.statusCode == 200 && response.data.isNotEmpty) {
      final String? downloadUrl = response.data['download_url'];
      if (downloadUrl != null) {
        // 使用获取到的下载链接
        await DownloadUtils.downloadFile(
          url: downloadUrl,
          savePath: '$gamePath${Platform.pathSeparator}authlib-injector.jar',
          onProgress: (progress) {
            final percent = (progress * 100).toStringAsFixed(2);
            LogUtil.log('正在下载AuthlibInjector: $percent%', level: 'INFO');
          },
          onSuccess: () {
            LogUtil.log('AuthlibInjector 下载完成', level: 'INFO');
          },
          onError: (error) {
            LogUtil.log('AuthlibInjector 下载失败: $error', level: 'ERROR');
          },
          onCancel: () {
            LogUtil.log('AuthlibInjector 下载已取消', level: 'WARNING');
          },
        );
      } else {
        throw '无法获取 authlib-injector 下载链接';
      }
    } else {
      throw '获取 authlib-injector 版本信息失败';
    }
  } catch (e) {
    LogUtil.log('获取 authlib-injector 信息失败: $e', level: 'ERROR');
    rethrow;
  }
}

// 外置登录令牌检查（传入的是加密的令牌）
Future<bool> checkToken(
  String url,
  String encryptedAccessToken,
  String encryptedClientToken,
) async {
  LogUtil.log('检查令牌有效性', level: 'INFO');
  String accessToken = await CryptoUtil.decrypt(encryptedAccessToken);
  String clientToken = await CryptoUtil.decrypt(encryptedClientToken);
  final options = Options(headers: {'Content-Type': 'application/json'});
  try {
    Map<String, dynamic> data = {
      'accessToken': accessToken,
      'clientToken': clientToken,
    };
    final response = await DioClient().dio.post(
      '$url/authserver/validate',
      data: data,
      options: options,
    );
    if (response.statusCode == 204) {
      LogUtil.log('令牌有效', level: 'INFO');
      return true;
    } else if (response.statusCode == 403) {
      LogUtil.log('令牌无效', level: 'WARNING');
      return false;
    } else {
      LogUtil.log('令牌检查失败，状态码: ${response.statusCode}', level: 'WARNING');
      return false;
    }
  } catch (e) {
    LogUtil.log('$url/authserver/validate令牌检查失败: $e', level: 'ERROR');
    return false;
  }
}

// 刷新外置登录令牌（传入的是加密的令牌，返回加密的新令牌）
Future<String> refreshToken(
  String url,
  String encryptedAccessToken,
  String encryptedClientToken,
  String name,
  String uuid,
) async {
  LogUtil.log('正在刷新令牌', level: 'INFO');
  String accessToken = await CryptoUtil.decrypt(encryptedAccessToken);
  String clientToken = await CryptoUtil.decrypt(encryptedClientToken);
  final options = Options(headers: {'Content-Type': 'application/json'});
  try {
    Map<String, dynamic> data = {
      'accessToken': accessToken,
      'clientToken': clientToken,
      "selectedProfile": {'name': name, 'id': uuid},
    };
    final response = await DioClient().dio.post(
      '$url/authserver/refresh',
      data: data,
      options: options,
    );
    if (response.statusCode == 200) {
      LogUtil.log('令牌刷新成功', level: 'INFO');
      String newAccessToken = response.data['accessToken'];
      return await CryptoUtil.encrypt(newAccessToken);
    } else {
      LogUtil.log('令牌刷新失败，状态码: ${response.statusCode}', level: 'WARNING');
      return encryptedAccessToken;
    }
  } catch (e) {
    LogUtil.log('令牌刷新失败: $e', level: 'ERROR');
    return encryptedAccessToken;
  }
}
