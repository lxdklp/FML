import 'dart:io';

import 'package:path/path.dart' as p;

/// 只使用程序的实际位置, 不依赖启动时的工作目录.
class AppLocation {
  const AppLocation({
    required this.platform,
    required this.programPath,
    required this.root,
    this.appImage = false,
  });

  final String platform;
  final String programPath;
  final String root;
  final bool appImage;

  static AppLocation detect({
    String? platform,
    String? executable,
    Map<String, String>? environment,
  }) {
    final os = platform ?? Platform.operatingSystem;
    final exe = executable ?? Platform.resolvedExecutable;
    final env = environment ?? Platform.environment;
    final path = p.Context(
      style: os == 'windows' ? p.Style.windows : p.Style.posix,
    );
    if (os == 'linux' && (env['APPIMAGE'] ?? '').isNotEmpty) {
      final original = env['APPIMAGE']!;
      return AppLocation(
        platform: os,
        programPath: original,
        root: path.dirname(original),
        appImage: true,
      );
    }
    if (os == 'macos') {
      var directory = path.dirname(exe);
      while (path.dirname(directory) != directory) {
        if (directory.endsWith('.app')) {
          return AppLocation(
            platform: os,
            programPath: directory,
            root: path.dirname(directory),
          );
        }
        directory = path.dirname(directory);
      }
    }
    return AppLocation(platform: os, programPath: exe, root: path.dirname(exe));
  }

  String get configPath => p.join(root, 'FML-data', 'settings.json');
}
