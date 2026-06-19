import 'dart:async';
import 'dart:io';
import 'package:fml/function/log.dart';
import 'package:fml/function/java/models/java_info.dart';
import 'package:fml/function/java/models/java_runtime.dart';
import 'package:win32_registry/win32_registry.dart';

class JavaUtils {
  JavaUtils._();

  ///
  /// Java 可执行文件名称
  ///
  static String _javaExecutableName = Platform.isWindows ? 'java.exe' : 'java';

  static final RegExp _vendorVersionRegExp = RegExp(
    r'(?:(OpenJDK|java|IBM|AdoptOpenJDK|Microsoft).*?)?version\s+"([^"]+)"',
    caseSensitive: false,
  );

  static final RegExp _fallbackVersionRegExp = RegExp(r'"([0-9._-]+)"');

  ///
  /// 寻找 Java 可执行文件
  ///
  static Future<List<JavaRuntime>> searchPotentialJavaExecutables({
    int searchDepth = 0,
  }) async {
    final Set<String> found = {};

    // 搜索PATH
    final pathSeparator = Platform.isWindows ? ';' : ':';
    final pathEntries =
        Platform.environment['PATH']?.split(pathSeparator) ?? [];

    for (final entry in pathEntries) {
      if (entry.trim().isEmpty) continue;

      final javaPath = _join(entry, _javaExecutableName);

      if (await File(javaPath).exists()) {
        found.add(await File(javaPath).resolveSymbolicLinks());
      }
    }

    // 搜索常用系统目录
    final List<Directory> candidates = [];

    if (Platform.isWindows) {
      final env = Platform.environment;
      final prog = env['ProgramFiles'] ?? 'C:\\Program Files';
      final progx86 = env['ProgramFiles(x86)'] ?? 'C:\\Program Files (x86)';

      candidates.add(Directory(prog));
      candidates.add(Directory(progx86));
    } else if (Platform.isLinux) {
      candidates.add(Directory('/usr/java'));
      candidates.add(Directory('/usr/lib/jvm'));
      candidates.add(Directory('/usr/lib32/jvm'));
      candidates.add(Directory('/usr/lib64/jvm'));

      final home = Platform.environment['HOME'];

      if (home != null) {
        candidates.add(Directory('$home/.sdkman/candidates/java'));
      }
    } else if (Platform.isMacOS) {
      candidates.add(Directory('/Library/Java/JavaVirtualMachines'));

      final home = Platform.environment['HOME'];

      if (home != null) {
        candidates.add(Directory('$home/Library/Java/JavaVirtualMachines'));
      }
    }

    // 搜索用户jdks
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

    if (home != null) candidates.add(Directory('$home/.jdks'));

    // 在Windows下通过注册表搜索
    if (Platform.isWindows) {
      final rootKeys = [RegistryHive.currentUser, RegistryHive.localMachine];

      // 大部分的注册表路径
      const paths = [
        r'SOFTWARE\JavaSoft\Java Runtime Environment',
        r'SOFTWARE\JavaSoft\Java Development Kit',
        r'SOFTWARE\JavaSoft\JDK',
        r'SOFTWARE\Wow6432Node\JavaSoft\Java Runtime Environment',
        r'SOFTWARE\Wow6432Node\JavaSoft\Java Development Kit',
        r'SOFTWARE\WOW6432Node\JavaSoft\JDK',
        r'SOFTWARE\AdoptOpenJDK\JDK',
        r'SOFTWARE\Microsoft\JDK',
        r'SOFTWARE\Azul Systems\Zulu',
        r'SOFTWARE\Amazon\Corretto',
        r'SOFTWARE\RedHat\OpenJDK\JDK',
        r'SOFTWARE\BellSoft\Liberica',
      ];

      for (final root in rootKeys) {
        for (final path in paths) {
          RegistryKey? key;

          try {
            key = Registry.openPath(root, path: path);

            // 枚举所有版本子键
            for (final versionKeyName in key.subkeyNames) {
              if (versionKeyName == 'null') continue;

              RegistryKey? versionKey;

              try {
                versionKey = Registry.openPath(
                  root,
                  path: '$path\\$versionKeyName',
                  desiredAccessRights: AccessRights.readOnly,
                );

                // 读取路径
                String? javaHome;
                try {
                  javaHome = versionKey.getStringValue('JavaHome');
                } catch (_) {}

                String? installationPath;
                try {
                  installationPath = versionKey.getStringValue(
                    'InstallationPath',
                  );
                } catch (_) {}

                final javaPath = javaHome ?? installationPath;

                if (javaPath != null && javaPath.isNotEmpty) {
                  candidates.add(Directory(javaPath));
                }
              } catch (_) {
                // 键不存在或无权限，跳过
              } finally {
                // 确保键被关闭
                versionKey?.close();
              }
            }
          } catch (e) {
            // 键不存在或无权限，跳过
          } finally {
            // 确保键被关闭
            key?.close();
          }
        }
      }
    }

    for (final dir in candidates) {
      if (!await dir.exists()) continue;

      try {
        await for (final entry in dir.list(followLinks: false)) {
          if (entry is Directory) {
            // 快速检查预期布局
            final javaHome = entry.path;
            final probes = _possibleExecutablePaths(javaHome);

            for (final p in probes) {
              final file = File(p);

              if (await file.exists()) {
                found.add(await file.resolveSymbolicLinks());
              }
            }
          }
        }
      } catch (e) {
        LogUtil.log('查找 Java 可执行文件时出错：$e', level: 'WARN');
      }
    }

    final List<JavaRuntime> result = [];

    // 同时检查每个候选目录下常见的顶级 JDK 名称
    // 并将其转换为JavaRuntime
    for (final exe in found) {
      try {
        final info = await probeJavaExecutable(exe);

        if (info != null) {
          final isJdk = await looksLikeJdk(exe);
          result.add(JavaRuntime(info: info, executable: exe, isJdk: isJdk));
        }
      } catch (e) {
        LogUtil.log('探测 Java 可执行文件时出错：$e', level: 'WARN');
      }
    }

    // 去重返回（按 executable 路径去重）
    final Map<String, JavaRuntime> uniqueByExecutable = {};

    for (final runtime in result) {
      // 后出现的同一路径会覆盖先前的，确保最终列表中每个 executable 唯一
      uniqueByExecutable[runtime.executable] = runtime;
    }

    return uniqueByExecutable.values.toList();
  }

  ///
  /// 可能的可执行文件路径
  ///
  static List<String> _possibleExecutablePaths(String javaHome) {
    final List<String> probes = [];

    if (Platform.isMacOS) {
      probes.add('$javaHome/jre.bundle/Contents/Home/bin/$_javaExecutableName');
      probes.add('$javaHome/Contents/Home/bin/$_javaExecutableName');
    }

    if (Platform.isWindows) {
      probes.add('$javaHome/$_javaExecutableName');
      probes.add('$javaHome/bin/$_javaExecutableName');
      probes.add('$javaHome/jre/bin/$_javaExecutableName');
    }

    return probes;
  }

  ///
  /// 检查可执行文件是否看为 JDK（存在 javac）
  ///
  static Future<bool> looksLikeJdk(String exe) async {
    try {
      final bin = File(exe).parent;
      final javac = File(
        '${bin.path}${Platform.pathSeparator}javac${Platform.isWindows ? '.exe' : ''}',
      );

      return await javac.exists();
    } catch (_) {
      return false;
    }
  }

  ///
  /// Java 可执行文件信息
  ///
  static Future<JavaInfo?> probeJavaExecutable(String exe) async {
    // 首先尝试“java -version”
    try {
      final proc = await Process.start(exe, ['-version']);
      final out = await proc.stderr.transform(SystemEncoding().decoder).join();
      await proc.exitCode;

      final parsed = parseVersionOutput(out);

      if (parsed != null) {
        return JavaInfo(
          version: parsed['version']!,
          vendor: parsed['vendor'],
          path: exe,
          os: Platform.operatingSystem,
          arch: Platform.version,
        );
      }
    } catch (e) {
      LogUtil.log('执行 "$exe -version" 时出错：$e', level: 'WARN');
    }

    // 尝试读取父目录中的发布文件
    try {
      final bin = File(exe).parent;
      final javaHome = bin.parent.path;
      final release = File('$javaHome${Platform.pathSeparator}release');

      if (await release.exists()) {
        final lines = await release.readAsLines();
        final map = <String, String>{};

        for (final line in lines) {
          final index = line.indexOf('=');
          if (index > 0) {
            final key = line.substring(0, index).trim();
            var value = line.substring(index + 1).trim();

            if (value.startsWith('"') && value.endsWith('"')) {
              value = value.substring(1, value.length - 1);
            }

            map[key] = value;
          }
        }

        final version = map['JAVA_VERSION'] ?? map['IMPLEMENTOR_VERSION'] ?? '';

        if (version.isNotEmpty) {
          return JavaInfo(
            version: version,
            vendor: map['IMPLEMENTOR'] ?? map['JAVA_VENDOR'],
            path: exe,
            os: Platform.operatingSystem,
            arch: Platform.version,
          );
        }
      }
    } catch (e) {
      LogUtil.log('读取 "$exe" 所在 JRE/JDK 的 release 文件时出错：$e', level: 'WARN');
    }
    return null;
  }

  ///
  /// 解析 "java -version" 输出
  ///
  static Map<String, String?>? parseVersionOutput(String output) {
    // 分割每行
    final lines = output.split('\n');

    for (final line in lines) {
      final trimmedLine = line.trim();

      if (trimmedLine.isEmpty) continue;

      final matches = _vendorVersionRegExp.firstMatch(trimmedLine);

      if (matches != null) {
        String? vendor;

        if (matches.group(1) == 'java') {
          vendor = 'Oracle';
        } else {
          vendor = matches.group(1);
        }

        final version = matches.group(2);
        return {'version': version ?? '', 'vendor': vendor};
      }

      final fallbackMatch = _fallbackVersionRegExp.firstMatch(line);

      if (fallbackMatch != null) {
        return {'version': fallbackMatch.group(1) ?? '', 'vendor': null};
      }
    }
    return null;
  }

  ///
  /// 获取系统默认 Java 信息
  ///
  static Future<JavaInfo?> getSystemDefaultJavaInfo() async {
    try {
      final javaVersionProcess = await Process.run('java', ['-version']);

      if (javaVersionProcess.exitCode != 0) {
        LogUtil.log(
          '获取系统默认 Java 信息失败，退出码：${javaVersionProcess.exitCode}',
          level: 'WARN',
        );
      }

      final versionOutput = (javaVersionProcess.stderr as String).isNotEmpty
          ? javaVersionProcess.stderr as String
          : javaVersionProcess.stdout as String;

      final parsedVersion = JavaUtils.parseVersionOutput(versionOutput);

      if (parsedVersion == null) {
        LogUtil.log('无法解析系统默认 Java 版本信息', level: 'WARN');
        return null;
      }

      String executablePath = '';

      try {
        if (Platform.isWindows) {
          final where = await Process.run('where', ['java']);

          if (where.exitCode == 0) {
            executablePath = (where.stdout as String)
                .toString()
                .split('\n')
                .first
                .trim();
          }
        } else {
          final which = await Process.run('which', ['java']);

          if (which.exitCode == 0) {
            executablePath = (which.stdout as String)
                .toString()
                .split('\n')
                .first
                .trim();
          }
        }
      } catch (e) {
        LogUtil.log('获取系统默认 Java 路径时出错：$e', level: 'WARN');
      }

      return JavaInfo(
        version: parsedVersion['version'] ?? 'unknown',
        vendor: parsedVersion['vendor'],
        path: executablePath,
        os: Platform.operatingSystem,
        arch: Platform.version,
      );
    } catch (e) {
      LogUtil.log('执行 "java -version" 时出错：$e', level: 'WARN');
      return null;
    }
  }

  ///
  /// 路径拼接
  ///
  static String _join(String a, String b) {
    if (a.endsWith(Platform.pathSeparator)) return '$a$b';
    return a + Platform.pathSeparator + b;
  }
}
