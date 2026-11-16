import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:fml/function/log.dart';

class CryptoUtil {
  static String? _cachedDeviceId;
  static final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();
  // 获取设备唯一标识符
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) {
      return _cachedDeviceId!;
    }
    try {
      String deviceId;
      if (Platform.isMacOS) {
        final macInfo = await _deviceInfoPlugin.macOsInfo;
        deviceId = macInfo.systemGUID ?? '';
      } else if (Platform.isWindows) {
        final windowsInfo = await _deviceInfoPlugin.windowsInfo;
        deviceId = windowsInfo.deviceId;
      } else if (Platform.isLinux) {
        final linuxInfo = await _deviceInfoPlugin.linuxInfo;
        deviceId = linuxInfo.machineId ?? '';
      } else {
        deviceId = '';
      }
      if (deviceId.trim().isEmpty) throw StateError('无法获取设备标识, 请重新登录');
      _cachedDeviceId = deviceId;
      return deviceId;
    } catch (e) {
      LogUtil.log('获取设备ID失败: $e', level: 'ERROR');
      throw StateError('无法获取设备标识, 不能保存登录凭据');
    }
  }

  static Future<String?> deviceFingerprint() async {
    try {
      return sha256.convert(utf8.encode(await getDeviceId())).toString();
    } catch (_) {
      return null;
    }
  }

  // 从设备ID生成AES密钥
  static Key _generateKey(String deviceId) {
    final hash = sha256.convert(utf8.encode(deviceId));
    return Key.fromUtf8(hash.toString().substring(0, 32));
  }

  // 从设备ID生成IV
  static IV _generateIV(String deviceId) {
    final hash = md5.convert(utf8.encode(deviceId));
    return IV.fromUtf8(hash.toString().substring(0, 16));
  }

  // 加密字符串
  static Future<String> encrypt(String plainText) async {
    if (plainText.isEmpty) {
      return '';
    }
    try {
      final deviceId = await getDeviceId();
      final key = _generateKey(deviceId);
      final iv = _generateIV(deviceId);
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      final encrypted = encrypter.encrypt(plainText, iv: iv);
      return encrypted.base64;
    } catch (e) {
      LogUtil.log('加密失败: $e', level: 'ERROR');
      throw StateError('无法加密登录凭据');
    }
  }

  // 解密字符串
  static Future<String> decrypt(String encryptedText) async {
    if (encryptedText.isEmpty) {
      return '';
    }
    try {
      final deviceId = await getDeviceId();
      final key = _generateKey(deviceId);
      final iv = _generateIV(deviceId);
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      final decrypted = encrypter.decrypt64(encryptedText, iv: iv);
      return decrypted;
    } catch (e) {
      LogUtil.log('解密失败: $e', level: 'ERROR');
      throw StateError('登录凭据无法解密, 请重新登录');
    }
  }
}
