import 'dart:async';
import 'dart:io';
import 'package:fml/function/log.dart';
import 'package:fml/function/java/models/java_info.dart';
import 'package:fml/function/java/models/java_runtime.dart';
import 'package:path/path.dart' as path;

class JavaManager {
  JavaManager._();

  ///
  /// Java 可执行文件名称
  ///
  static String kJavaExecutableName = Platform.isWindows ? 'java.exe' : 'java';

  static final RegExp _vendorVersionRegExp = RegExp(
    r'(?:(OpenJDK|java|IBM|AdoptOpenJDK|Microsoft).*?)?version\s+"([^"]+)"',
    caseSensitive: false,
  );

  static final RegExp _fallbackVersionRegExp = RegExp(r'"([0-9._-]+)"');

  ///
  /// 寻找 Java 可执行文件
  ///
  static Future<List<JavaRuntime>> searchPotentialJavaExecutables({
    int searchDepth = 4,
  }) async {
    final Set<String> found = {};
    final List<JavaRuntime> result = [];

    // PATH
    final pathSeparator = Platform.isWindows ? ';' : ':';
    final pathEntries =
        Platform.environment['PATH']?.split(pathSeparator) ?? [];

    for (final entry in pathEntries) {
      if (entry.trim().isEmpty) continue;

      final javaPath = _join(entry, kJavaExecutableName);

      if (await File(javaPath).exists()) {
        found.add(await File(javaPath).resolveSymbolicLinks());
      }
    }

    // 常用系统目录
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

    // 用户jdks
    final home = Platform.environment['HOME'];

    if (home != null) candidates.add(Directory('$home/.jdks'));

    for (final dir in candidates) {
      if (!await dir.exists()) continue;

      try {
        await for (final entry in dir.list(followLinks: false)) {
          if (entry is Directory) {
            // 快速检查预期布局
            final javaHome = entry.path;
            final probes = _possibleExecutablePaths(javaHome);
            for (final p in probes) {
              final f = File(p);
              if (await f.exists()) found.add(await f.resolveSymbolicLinks());
            }
          }
        }
      } catch (e) {
        LogUtil.log('查找 Java 可执行文件时出错：$e', level: 'WARN');
      }
    }

    // 同时检查每个候选目录下常见的顶级 JDK 名称
    for (final exe in found) {
      try {
        final info = await _probeJavaExecutable(exe);

        if (info != null) {
          final isJdk = await _looksLikeJdk(exe);
          result.add(JavaRuntime(info: info, executable: exe, isJdk: isJdk));
        }
      } catch (e) {
        LogUtil.log('探测 Java 可执行文件时出错：$e', level: 'WARN');
      }
    }

    final roots = <Directory>[];

    if (Platform.isWindows) {
      // Windows枚举
      for (int i = 0; i < 26; i++) {
        // CharCode 68（排除A,B,C）
        final drive = '${String.fromCharCode(68 + i)}:\\';
        final dir = Directory(drive);

        try {
          if (dir.existsSync()) {
            roots.add(dir);
          }
        } catch (_) {
          // 忽略无法访问的驱动器
        }
      }

      //final stopwatch = Stopwatch()..start();
      for (final rootDir in roots) {
        final javaRuntimes = await _searchJavaInDirRecursive(
          dir: rootDir,
          searchDepth: searchDepth,
        );

        result.addAll(javaRuntimes);
      }
      //stopwatch.stop();

      //print('timeee: ${stopwatch.elapsedMilliseconds} ms, $result');
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
  /// 递归搜索Java运行时
  ///
  /// [dir]           要搜索的根目录
  /// [searchDepth]   最大允许的递归深度
  /// [currentDepth]  当前递归深度（内部调用使用）
  ///
  static Future<List<JavaRuntime>> _searchJavaInDirRecursive({
    required Directory dir,
    required int searchDepth,
    int currentDepth = 0,
  }) async {
    List<JavaRuntime> result = [];

    if (currentDepth > searchDepth) return result;

    try {
      // 检查当前目录下的文件
      final dirs = dir.list(followLinks: false);

      await for (final entity in dirs) {
        final name = path.basename(entity.path);

        // 排除 . 开头目录
        if (name.startsWith('.')) continue;

        if (entity is File) {
          final lowerFileName = name.toLowerCase();

          if (lowerFileName == kJavaExecutableName) {
            // 创建JavaRuntime逻辑
            final exePath = entity.path;
            final info = await _probeJavaExecutable(exePath);

            if (info != null) {
              final isJdk = await _looksLikeJdk(exePath);

              result.add(
                JavaRuntime(info: info, executable: exePath, isJdk: isJdk),
              );
            }
          }
        } else if (entity is Directory) {
          // 递归搜索子目录（深度+1）
          result.addAll(
            await _searchJavaInDirRecursive(
              dir: entity,
              currentDepth: currentDepth + 1,
              searchDepth: searchDepth,
            ),
          );
        }
      }
    } catch (e) {
      // 忽略权限错误或无法访问的目录
    }

    return result;
  }

  ///
  /// 可能的可执行文件路径
  ///
  static List<String> _possibleExecutablePaths(String javaHome) {
    final List<String> probes = [];

    if (Platform.isMacOS) {
      probes.add('$javaHome/jre.bundle/Contents/Home/bin/$kJavaExecutableName');

      probes.add('$javaHome/Contents/Home/bin/$kJavaExecutableName');
    }

    probes.add('$javaHome/bin/$kJavaExecutableName');
    probes.add('$javaHome/jre/bin/$kJavaExecutableName');
    return probes;
  }

  ///
  /// 检查可执行文件是否看为 JDK（存在 javac）
  ///
  static Future<bool> _looksLikeJdk(String exe) async {
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
  static Future<JavaInfo?> _probeJavaExecutable(String exe) async {
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
  /// 路径拼接
  ///
  static String _join(String a, String b) {
    if (a.endsWith(Platform.pathSeparator)) return '$a$b';
    return a + Platform.pathSeparator + b;
  }
}
