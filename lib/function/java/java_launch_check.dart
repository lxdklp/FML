import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'java_service.dart';
import 'java_utils.dart';
import 'models/java_info.dart';

String configuredJavaExecutable(SharedPreferences prefs) {
  final selected =
      prefs.getString('javaSelectedPath') ?? JavaService.javaSelectedPath;
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
    this.actualVersion,
  });

  final String executable;
  final String? minecraft;
  final int? expectedMajor;
  final String? actualVersion;

  int? get actualMajor =>
      actualVersion == null ? null : javaMajorVersion(actualVersion!);
  bool get needsWarning =>
      expectedMajor == null ||
      actualMajor == null ||
      expectedMajor != actualMajor;

  String get message {
    final expected = expectedMajor == null
        ? '无法读取此游戏声明的 Java 版本。'
        : 'Minecraft ${minecraft ?? ''} 的版本文件声明使用 Java $expectedMajor。';
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
    }
  } catch (_) {
    // Missing or invalid metadata cannot establish Java compatibility.
  }
  JavaInfo? info;
  try {
    info = await probe(executable).timeout(const Duration(seconds: 5));
  } catch (_) {
    // An inconclusive check also allows the user to authorize a launch.
  }
  return JavaLaunchCheck(
    executable: executable,
    minecraft: minecraft,
    expectedMajor: expectedMajor,
    actualVersion: info?.version,
  );
}
