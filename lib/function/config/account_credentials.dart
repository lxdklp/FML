import 'app_config.dart';

class AccountCredentials {
  static const deviceKey = '_fmlDeviceFingerprint';

  /// 普通版首次升级保留原凭据, 导出的快照携带设备指纹供下次启动校验
  static Future<void> bindDevice(AppConfig config, String? fingerprint) async {
    await config.edit((data) {
      final old = data[deviceKey] as String?;
      if (fingerprint == null ||
          old != null && old != fingerprint ||
          old == null && !config.canExportPortable) {
        for (final key in data.keys.toList()) {
          if (key.startsWith('online_account_')) {
            final account = List<String>.from(data[key] as List);
            if (account.length > 2) account[2] = '';
            data[key] = account;
          } else if (key.startsWith('external_account_')) {
            final account = List<String>.from(data[key] as List);
            for (var i = 4; i < account.length; i++) {
              account[i] = '';
            }
            data[key] = account;
          } else if (key.startsWith('Account_')) {
            // 清理历史选中账号副本
            data.remove(key);
          }
        }
      }
      if (fingerprint != null) {
        data[deviceKey] = fingerprint;
      } else {
        data.remove(deviceKey);
      }
    });
  }

  static bool needsLogin(List<String>? account, String type) => switch (type) {
    '1' => account == null || account.length < 3 || account[2].isEmpty,
    '2' =>
      account == null ||
          account.length < 7 ||
          account[4].isEmpty ||
          account[5].isEmpty ||
          account[6].isEmpty,
    _ => false,
  };
}
