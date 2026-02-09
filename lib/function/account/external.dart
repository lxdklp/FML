import 'package:dio/dio.dart';
import 'package:fml/function/dio_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:fml/function/log.dart';
import 'package:fml/function/crypto_util.dart';

// 认证响应模型
class AuthResponse {
  final String accessToken;
  final String clientToken;
  final List<Profile> availableProfiles;
  final Profile? selectedProfile;
  final User? user;

  AuthResponse({
    required this.accessToken,
    required this.clientToken,
    required this.availableProfiles,
    this.selectedProfile,
    this.user,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: json['accessToken'],
      clientToken: json['clientToken'],
      availableProfiles: (json['availableProfiles'] as List)
          .map((profile) => Profile.fromJson(profile))
          .toList(),
      selectedProfile: json['selectedProfile'] != null
          ? Profile.fromJson(json['selectedProfile'])
          : null,
      user: json['user'] != null ? User.fromJson(json['user']) : null,
    );
  }
}

class Profile {
  final String id;
  final String name;

  Profile({required this.id, required this.name});

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(id: json['id'], name: json['name']);
  }
}

class User {
  final String id;

  User({required this.id});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(id: json['id']);
  }
}

// 向外置登录服务器发送认证请求
Future<AuthResponse> authenticate(
  String serverUrl,
  String username,
  String password,
) async {
  try {
    LogUtil.log('开始认证外置登录: $serverUrl, 用户名: $username', level: 'INFO');
    final response = await DioClient().dio.post(
      '$serverUrl/authserver/authenticate',
      options: Options(
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        validateStatus: (status) {
          return status! < 500;
        },
      ),
      data: {
        'username': username,
        'password': password,
        'requestUser': true,
        'agent': {'name': 'Minecraft', 'version': 1},
      },
    );

    if (response.statusCode == 200) {
      LogUtil.log('外置登录认证成功: $serverUrl, 用户名: $username', level: 'INFO');
      return AuthResponse.fromJson(response.data);
    } else {
      String errorMessage = '未知错误';
      if (response.data is Map) {
        Map<String, dynamic> errorData = response.data as Map<String, dynamic>;
        String errorType = errorData['error'] ?? '未知错误类型';
        String errorDetail = errorData['errorMessage'] ?? '';
        LogUtil.log(
          '外置登录认证失败: 错误类型: $errorType, 错误信息: $errorDetail',
          level: 'ERROR',
        );
        if (errorType == 'ForbiddenOperationException' &&
            errorDetail.contains('用户名或密码错误')) {
          errorMessage = '用户名或密码错误，请检查后重试';
        } else {
          errorMessage = '$errorType: $errorDetail';
        }
      } else {
        LogUtil.log(
          '外置登录认证失败: 状态码: ${response.statusCode}, 响应: ${response.data}',
          level: 'ERROR',
        );
        errorMessage = '认证失败，状态码: ${response.statusCode}';
      }
      throw Exception(errorMessage);
    }
  } on DioException catch (e) {
    String errorMessage;
    if (e.response != null) {
      try {
        if (e.response!.data is Map) {
          Map<String, dynamic> errorData =
              e.response!.data as Map<String, dynamic>;
          String errorType = errorData['error'] ?? '未知错误类型';
          String errorDetail = errorData['errorMessage'] ?? '';
          LogUtil.log('外置登录Dio异常: $errorType - $errorDetail', level: 'ERROR');
          if (errorType == 'ForbiddenOperationException' &&
              errorDetail.contains('用户名或密码错误')) {
            errorMessage = '用户名或密码错误，请检查后重试';
          } else {
            errorMessage = '$errorType: $errorDetail';
          }
        } else {
          errorMessage = '请求失败: ${e.response?.statusMessage}';
          LogUtil.log(
            '外置登录请求异常: 状态码: ${e.response?.statusCode}, 消息: ${e.response?.statusMessage}',
            level: 'ERROR',
          );
        }
      } catch (_) {
        errorMessage = '解析错误响应失败: ${e.message}';
        LogUtil.log('外置登录请求异常: 解析错误响应失败', level: 'ERROR');
      }
    } else if (e.type == DioExceptionType.connectionTimeout) {
      errorMessage = '连接超时，请检查网络设置';
      LogUtil.log('外置登录请求异常: 连接超时', level: 'ERROR');
    } else if (e.type == DioExceptionType.sendTimeout) {
      errorMessage = '发送请求超时，请稍后重试';
      LogUtil.log('外置登录请求异常: 发送超时', level: 'ERROR');
    } else if (e.type == DioExceptionType.receiveTimeout) {
      errorMessage = '接收响应超时，请稍后重试';
      LogUtil.log('外置登录请求异常: 接收超时', level: 'ERROR');
    } else {
      errorMessage = '连接服务器失败: ${e.message}';
      LogUtil.log('外置登录请求异常: ${e.message}', level: 'ERROR');
    }
    throw Exception(errorMessage);
  } catch (e) {
    LogUtil.log('外置登录其他错误: $e', level: 'ERROR');
    throw Exception('请求出错: $e');
  }
}

// 保存单个外置登录账户信息
Future<void> _saveAccount(
  String name,
  String uuid,
  String serverUrl,
  String username,
  String password,
  String accessToken,
  String clientToken,
) async {
  final prefs = await SharedPreferences.getInstance();
  List<String> accounts = prefs.getStringList('AccountsList') ?? [];
  if (!accounts.contains(name)) {
    accounts.add(name);
    await prefs.setStringList('external_accounts_list', accounts);
    LogUtil.log('添加账号到列表: $name', level: 'INFO');
  } else {
    LogUtil.log('账号已存在，更新账号信息: $name', level: 'INFO');
  }
  String encryptedPassword = await CryptoUtil.encrypt(password);
  String encryptedAccessToken = await CryptoUtil.encrypt(accessToken);
  String encryptedClientToken = await CryptoUtil.encrypt(clientToken);
  await prefs.setStringList('external_account_$name', [
    '2',
    uuid,
    serverUrl,
    username,
    encryptedPassword,
    encryptedAccessToken,
    encryptedClientToken,
  ]);
  LogUtil.log('账号保存成功: $name, UUID: $uuid', level: 'INFO');
}

// 保存外置登录账户信息（多账号情况）
Future<void> saveAuthLibInjectorAccount(
  BuildContext context,
  String serverUrl,
  String username,
  String password,
) async {
  try {
    // 验证输入
    if (serverUrl.isEmpty || username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写完整的外置登录信息')));
      return;
    }
    String formattedUrl = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    AuthResponse authResponse = await authenticate(
      formattedUrl,
      username,
      password,
    );
    if (authResponse.availableProfiles.isEmpty) {
      LogUtil.log('没有可用的游戏账号', level: 'WARN');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可用的游戏账号')));
      return;
    }
    if (authResponse.selectedProfile != null) {
      String name = authResponse.selectedProfile!.name;
      String uuid = authResponse.selectedProfile!.id;
      await _saveAccount(
        name,
        uuid,
        serverUrl,
        username,
        password,
        authResponse.accessToken,
        authResponse.clientToken,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已添加外置登录账号: $name')));
      Navigator.pop(context);
      return;
    }
    if (authResponse.availableProfiles.length > 1) {
      LogUtil.log(
        '发现多个可用账号，数量: ${authResponse.availableProfiles.length}',
        level: 'INFO',
      );
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('选择要添加的账号'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    title: const Text('添加所有账号'),
                    onTap: () async {
                      Navigator.pop(context);
                      for (var profile in authResponse.availableProfiles) {
                        await _saveAccount(
                          profile.name,
                          profile.id,
                          serverUrl,
                          username,
                          password,
                          authResponse.accessToken,
                          authResponse.clientToken,
                        );
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '已添加${authResponse.availableProfiles.length}个外置登录账号',
                          ),
                        ),
                      );
                      Navigator.pop(context);
                    },
                  ),
                  const Divider(),
                  ...authResponse.availableProfiles.map(
                    (profile) => ListTile(
                      title: Text(profile.name),
                      subtitle: Text('UUID: ${profile.id}'),
                      onTap: () async {
                        Navigator.pop(context);
                        await _saveAccount(
                          profile.name,
                          profile.id,
                          serverUrl,
                          username,
                          password,
                          authResponse.accessToken,
                          authResponse.clientToken,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已添加外置登录账号: ${profile.name}')),
                        );
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      Profile profile = authResponse.availableProfiles.first;
      await _saveAccount(
        profile.name,
        profile.id,
        serverUrl,
        username,
        password,
        authResponse.accessToken,
        authResponse.clientToken,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已添加外置登录账号: ${profile.name}')));
      Navigator.pop(context);
    }
  } catch (e) {
    LogUtil.log('添加外置登录账号失败: $e', level: 'ERROR');
    String errorMessage = e.toString();
    if (errorMessage.contains('Exception: ')) {
      errorMessage = errorMessage.replaceFirst('Exception: ', '');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('认证失败: $errorMessage'),
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
