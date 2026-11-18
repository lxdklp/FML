import 'dart:convert';
import 'dart:io';

import 'package:fml/function/config/app_config.dart';

import 'java_service.dart';
import 'java_utils.dart';
import 'models/java_info.dart';

Future<String> configuredJavaExecutable(AppConfig prefs) async {
  final selected =
      (await prefs.getString('javaSelectedPath')) ??
      JavaService.javaSelectedPath;
  return selected.isEmpty ? 'java' : selected;
}

int? javaMajorVersion(String version) {
  final parts = version.trim().split(RegExp(r'[._+\-]'));
  final major = int.tryParse(
    parts.first == '1' && parts.length > 1 ? parts[1] : parts.first,
  );
  return major != null && major > 0 ? major : null;
}

class JavaLaunchCheck {
  const JavaLaunchCheck({
    required this.executable,
    this.minecraft,
    this.expectedMajor,
    this.compatibleJavaMajors,
    this.actualVersion,
  });

  final String executable;
  final String? minecraft;
  final int? expectedMajor;
  final List<int>? compatibleJavaMajors;
  final String? actualVersion;

  int? get actualMajor =>
      actualVersion == null ? null : javaMajorVersion(actualVersion!);
  bool get _hasValidCompatibleJavaMajors =>
      compatibleJavaMajors != null &&
      compatibleJavaMajors!.isNotEmpty &&
      compatibleJavaMajors!.every((major) => major > 0);

  bool get needsWarning {
    if (compatibleJavaMajors != null) {
      return !_hasValidCompatibleJavaMajors ||
          actualMajor == null ||
          !compatibleJavaMajors!.contains(actualMajor);
    }
    return expectedMajor == null ||
        actualMajor == null ||
        expectedMajor != actualMajor;
  }

  String get message {
    final String expected;
    if (compatibleJavaMajors != null) {
      expected = _hasValidCompatibleJavaMajors
          ? '此游戏组件声明的兼容 Java 主版本集合为：${compatibleJavaMajors!.join('、')}。'
          : '无法读取此游戏组件声明的 Java 兼容版本集合。';
    } else {
      expected = expectedMajor == null
          ? '无法读取此游戏声明的 Java 版本。'
          : 'Minecraft ${minecraft ?? ''} 的版本文件声明使用 Java $expectedMajor。';
    }
    final actual = actualMajor == null
        ? '无法识别当前选择的 Java 版本。'
        : '当前选择的是 Java $actualVersion。';
    return '$expected\n$actual\n\nJava 路径：$executable\n\n'
        '继续启动可能出现兼容性问题。你可以取消并在设置中更换 Java，或授权本次仍然启动。';
  }
}

Future<JavaLaunchCheck> checkLaunchJava({
  required String metadataPath,
  required String executable,
  Future<JavaInfo?> Function(String) probe = JavaUtils.probeJavaExecutable,
}) async {
  String? minecraft;
  int? expectedMajor;
  List<int>? compatibleJavaMajors;
  try {
    final metadata = jsonDecode(await File(metadataPath).readAsString());
    if (metadata is Map) {
      if (metadata['id'] is String) minecraft = metadata['id'];
      final java = metadata['javaVersion'];
      if (java is Map &&
          java['majorVersion'] is int &&
          java['majorVersion'] > 0) {
        expectedMajor = java['majorVersion'];
      }
      if (metadata.containsKey('compatibleJavaMajors')) {
        final compatible = metadata['compatibleJavaMajors'];
        compatibleJavaMajors =
            compatible is List &&
                compatible.isNotEmpty &&
                compatible.every((major) => major is int && major > 0)
            ? List<int>.unmodifiable(compatible.cast<int>())
            : const [];
      }
    }
  } catch (_) {
    // 元数据缺失或无效时无法确认 Java 兼容性.
  }
  JavaInfo? info;
  try {
    info = await probe(executable).timeout(const Duration(seconds: 5));
  } catch (_) {
    // 检查失败时仍允许用户授权本次启动.
  }
  return JavaLaunchCheck(
    executable: executable,
    minecraft: minecraft,
    expectedMajor: expectedMajor,
    compatibleJavaMajors: compatibleJavaMajors,
    actualVersion: info?.version,
  );
}
