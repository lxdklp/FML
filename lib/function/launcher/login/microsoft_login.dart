import 'package:dio/dio.dart';
import 'package:fml/function/dio_client.dart';
import 'package:fml/function/log.dart';
import 'package:fml/function/crypto_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 登录模式
String _getLoginMode(String loginMode) {
  switch (loginMode) {
    case '0':
      return 'offline';
    case '1':
      return 'online';
    case '2':
      return 'external';
    default:
      return 'unknown';
  }
}

// 获取微软账号令牌
Future<String> _getMsToken(String refreshToken) async {
  final prefs = await SharedPreferences.getInstance();
  String decryptedRefreshToken = await CryptoUtil.decrypt(refreshToken);
  const int maxRetries = 3;
  int attempt = 0;
  while (attempt < maxRetries) {
    attempt++;
    try {
      final response = await DioClient().dio.post(
        'https://login.microsoftonline.com/consumers/oauth2/v2.0/token',
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
        data: {
          'client_id': '3847de77-c7ca-4daa-a0b7-50850446d58c',
          'grant_type': 'refresh_token',
          'scope': 'XboxLive.signin offline_access',
          'refresh_token': decryptedRefreshToken,
        },
      );
      if (response.statusCode == 200) {
        if (response.data is Map) {
          Map<String, dynamic> data = response.data as Map<String, dynamic>;
          String accessToken = data['access_token'] ?? '';
          String newRefreshToken = data['refresh_token'] ?? '';
          if (accessToken.isNotEmpty && newRefreshToken.isNotEmpty) {
            final accountName = prefs.getString('SelectedAccountName') ?? '';
            final accountType = prefs.getString('SelectedAccountType') ?? '';
            final accountInfo =
                prefs.getStringList(
                  '${_getLoginMode(accountType)}_account_$accountName',
                ) ??
                [];
            String encryptedRefreshToken = await CryptoUtil.encrypt(
              newRefreshToken,
            );
            prefs.setStringList(
              '${_getLoginMode(accountType)}_account_$accountName',
              [accountInfo[0], accountInfo[1], encryptedRefreshToken],
            );
            return accessToken;
          } else {
            LogUtil.log('无法获取微软账号令牌', level: 'ERROR');
          }
        }
      } else {
        LogUtil.log(
          '请求微软账号令牌失败: 状态码: ${response.statusCode}, 响应: ${response.data}',
          level: 'ERROR',
        );
      }
    } on DioException catch (e) {
      if (e.response != null) {
        try {
          if (e.response!.data is Map) {
            Map<String, dynamic> errorData =
                e.response!.data as Map<String, dynamic>;
            String errorType = errorData['error'] ?? '未知错误类型';
            String errorDetail = errorData['error_description'] ?? '';
            LogUtil.log('Dio异常: $errorType - $errorDetail', level: 'ERROR');
            if (errorType == 'slow_down') {
              await Future.delayed(const Duration(seconds: 5));
            }
          } else {
            LogUtil.log(
              '请求微软账号令牌异常: 状态码: ${e.response?.statusCode}, 消息: ${e.response?.statusMessage}',
              level: 'ERROR',
            );
          }
        } catch (_) {
          LogUtil.log('请求微软账号令牌异常: 解析错误响应失败', level: 'ERROR');
        }
      } else if (e.type == DioExceptionType.connectionTimeout) {
        LogUtil.log('请求微软账号令牌异常: 连接超时', level: 'ERROR');
      } else if (e.type == DioExceptionType.sendTimeout) {
        LogUtil.log('请求微软账号令牌异常: 发送超时', level: 'ERROR');
      } else if (e.type == DioExceptionType.receiveTimeout) {
        LogUtil.log('请求微软账号令牌异常: 接收超时', level: 'ERROR');
      } else {
        LogUtil.log('请求微软账号令牌异常: ${e.message}', level: 'ERROR');
      }
    } catch (e) {
      LogUtil.log('请求微软账号令牌发生其他错误: $e', level: 'ERROR');
    }
    if (attempt < maxRetries) {
      LogUtil.log(
        '获取微软账号令牌失败,正在进行第 $attempt 次重试 (最多 $maxRetries 次)',
        level: 'WARNING',
      );
    }
  }
  LogUtil.log('多次尝试后仍无法获取微软账号令牌', level: 'ERROR');
  return '';
}

// 获取 Xbox Live令牌
Future<String> _getXboxLiveToken(msToken) async {
  try {
    final response = await DioClient().dio.post(
      'https://user.auth.xboxlive.com/user/authenticate',
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
      data: {
        'Properties': {
          'AuthMethod': 'RPS',
          'SiteName': 'user.auth.xboxlive.com',
          'RpsTicket': 'd=$msToken',
        },
        'RelyingParty': 'http://auth.xboxlive.com',
        'TokenType': 'JWT',
      },
    );
    if (response.statusCode == 200) {
      if (response.data is Map) {
        Map<String, dynamic> data = response.data as Map<String, dynamic>;
        String token = data['Token'] ?? '';
        if (token.isNotEmpty) {
          return token;
        } else {
          LogUtil.log('无法获取 Xbox Live 令牌', level: 'ERROR');
        }
      }
    } else {
      LogUtil.log(
        '请求 Xbox Live 令牌失败: 状态码: ${response.statusCode}, 响应: ${response.data}',
        level: 'ERROR',
      );
    }
  } on DioException catch (e) {
    if (e.response != null) {
      try {
        if (e.response!.data is Map) {
          Map<String, dynamic> errorData =
              e.response!.data as Map<String, dynamic>;
          String errorType = errorData['error'] ?? '未知错误类型';
          String errorDetail = errorData['errorMessage'] ?? '';
          LogUtil.log('Dio异常: $errorType - $errorDetail', level: 'ERROR');
        } else {
          LogUtil.log(
            '获取 Xbox Live 令牌异常: 状态码: ${e.response?.statusCode}, 消息: ${e.response?.statusMessage}',
            level: 'ERROR',
          );
        }
      } catch (_) {
        LogUtil.log('获取 Xbox Live 令牌异常: 解析错误响应失败', level: 'ERROR');
      }
    } else if (e.type == DioExceptionType.connectionTimeout) {
      LogUtil.log('获取 Xbox Live 令牌异常: 连接超时', level: 'ERROR');
    } else if (e.type == DioExceptionType.sendTimeout) {
      LogUtil.log('获取 Xbox Live 令牌异常: 发送超时', level: 'ERROR');
    } else if (e.type == DioExceptionType.receiveTimeout) {
      LogUtil.log('获取 Xbox Live 令牌异常: 接收超时', level: 'ERROR');
    } else {
      LogUtil.log('获取 Xbox Live 令牌异常: ${e.message}', level: 'ERROR');
    }
  } catch (e) {
    LogUtil.log('获取 Xbox Live 令牌发生其他错误: $e', level: 'ERROR');
  }
  return '';
}

// 获取 XSTS 令牌
Future<List<String>> _getXSTSToken(xblToken) async {
  try {
    final response = await DioClient().dio.post(
      'https://xsts.auth.xboxlive.com/xsts/authorize',
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
      data: {
        'Properties': {
          'SandboxId': 'RETAIL',
          'UserTokens': [xblToken],
        },
        'RelyingParty': 'rp://api.minecraftservices.com/',
        'TokenType': 'JWT',
      },
    );
    if (response.statusCode == 200) {
      if (response.data is Map) {
        Map<String, dynamic> data = response.data as Map<String, dynamic>;
        String token = data['Token'] ?? '';
        String userHash = '';
        if (data['DisplayClaims'] is Map &&
            data['DisplayClaims']['xui'] is List &&
            data['DisplayClaims']['xui'].isNotEmpty) {
          userHash = data['DisplayClaims']['xui'][0]['uhs'] ?? '';
        }
        if (token.isNotEmpty && userHash.isNotEmpty) {
          return [token, userHash];
        } else {
          LogUtil.log('无法获取 XSTS 令牌', level: 'ERROR');
        }
      }
    } else {
      LogUtil.log(
        '请求 XSTS 令牌失败: 状态码: ${response.statusCode}, 响应: ${response.data}',
        level: 'ERROR',
      );
    }
  } on DioException catch (e) {
    if (e.response != null) {
      try {
        if (e.response!.data is Map) {
          Map<String, dynamic> errorData =
              e.response!.data as Map<String, dynamic>;
          String errorType = errorData['error'] ?? '未知错误类型';
          String errorDetail = errorData['errorMessage'] ?? '';
          LogUtil.log('Dio异常: $errorType - $errorDetail', level: 'ERROR');
        } else {
          LogUtil.log(
            '获取 XSTS 令牌异常: 状态码: ${e.response?.statusCode}, 消息: ${e.response?.statusMessage}',
            level: 'ERROR',
          );
        }
      } catch (_) {
        LogUtil.log('获取 XSTS 令牌异常: 解析错误响应失败', level: 'ERROR');
      }
    } else if (e.type == DioExceptionType.connectionTimeout) {
      LogUtil.log('获取 XSTS 令牌异常: 连接超时', level: 'ERROR');
    } else if (e.type == DioExceptionType.sendTimeout) {
      LogUtil.log('获取 XSTS 令牌异常: 发送超时', level: 'ERROR');
    } else if (e.type == DioExceptionType.receiveTimeout) {
      LogUtil.log('获取 XSTS 令牌异常: 接收超时', level: 'ERROR');
    } else {
      LogUtil.log('获取 XSTS 令牌异常: ${e.message}', level: 'ERROR');
    }
  } catch (e) {
    LogUtil.log('获取 XSTS 令牌发生其他错误: $e', level: 'ERROR');
  }
  return ['', ''];
}

// 获取 Minecraft 令牌
Future<String> _getMcToken(xstsToken) async {
  try {
    final response = await DioClient().dio.post(
      'https://api.minecraftservices.com/authentication/login_with_xbox',
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
      data: {'identityToken': 'XBL3.0 x=${xstsToken[1]};${xstsToken[0]}'},
    );
    if (response.statusCode == 200) {
      if (response.data is Map) {
        Map<String, dynamic> data = response.data as Map<String, dynamic>;
        String token = data['access_token'] ?? '';
        if (token.isNotEmpty) {
          return token;
        } else {
          LogUtil.log('无法获取 Minecraft 令牌', level: 'ERROR');
        }
      }
    } else {
      LogUtil.log(
        '请求 Minecraft 令牌失败: 状态码: ${response.statusCode}, 响应: ${response.data}',
        level: 'ERROR',
      );
    }
  } on DioException catch (e) {
    if (e.response != null) {
      try {
        if (e.response!.data is Map) {
          Map<String, dynamic> errorData =
              e.response!.data as Map<String, dynamic>;
          String errorType = errorData['error'] ?? '未知错误类型';
          String errorDetail = errorData['errorMessage'] ?? '';
          LogUtil.log('Dio异常: $errorType - $errorDetail', level: 'ERROR');
        } else {
          LogUtil.log(
            '获取 Minecraft 令牌异常: 状态码: ${e.response?.statusCode}, 消息: ${e.response?.statusMessage}',
            level: 'ERROR',
          );
        }
      } catch (_) {
        LogUtil.log('获取 Minecraft 令牌异常: 解析错误响应失败', level: 'ERROR');
      }
    } else if (e.type == DioExceptionType.connectionTimeout) {
      LogUtil.log('获取 Minecraft 令牌异常: 连接超时', level: 'ERROR');
    } else if (e.type == DioExceptionType.sendTimeout) {
      LogUtil.log('获取 Minecraft 令牌异常: 发送超时', level: 'ERROR');
    } else if (e.type == DioExceptionType.receiveTimeout) {
      LogUtil.log('获取 Minecraft 令牌异常: 接收超时', level: 'ERROR');
    } else {
      LogUtil.log('获取 Minecraft 令牌异常: ${e.message}', level: 'ERROR');
    }
  } catch (e) {
    LogUtil.log('获取 Minecraft 令牌发生其他错误: $e', level: 'ERROR');
  }
  return '';
}

// 登录
Future<String> login(String refreshToken) async {
  String msToken = await _getMsToken(refreshToken);
  if (msToken.isEmpty) {
    LogUtil.log('登录失败: 无法获取微软账号令牌', level: 'ERROR');
    return '';
  }
  String xblToken = await _getXboxLiveToken(msToken);
  if (xblToken.isEmpty) {
    LogUtil.log('登录失败: 无法获取Xbox Live令牌', level: 'ERROR');
    return '';
  }
  List<String> xstsToken = await _getXSTSToken(xblToken);
  if (xstsToken[0].isEmpty || xstsToken[1].isEmpty) {
    LogUtil.log('登录失败: 无法获取XSTS令牌', level: 'ERROR');
    return '';
  }
  String mcToken = await _getMcToken(xstsToken);
  if (mcToken.isEmpty) {
    LogUtil.log('登录失败: 无法获取Minecraft令牌', level: 'ERROR');
    return '';
  }
  return mcToken;
}
