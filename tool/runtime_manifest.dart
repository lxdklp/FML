import 'dart:convert';
import 'dart:io';

// 在构建产物目录生成清单
Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('需要提供构建产物目录');
  final root = Directory(args.single).absolute;
  final paths = <String>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    final relative = entity.path
        .substring(
          root.path.length +
              (root.path.endsWith(Platform.pathSeparator) ? 0 : 1),
        )
        .replaceAll('\\', '/');
    if (relative == 'fml-runtime-files.json' ||
        relative.startsWith('FML-data/') ||
        relative == 'FML-data' ||
        relative.endsWith('.pdb') ||
        relative.startsWith('unins')) {
      continue;
    }
    paths.add(relative);
  }
  paths.sort();
  await File('${root.path}/fml-runtime-files.json')
      .writeAsString(jsonEncode(paths), flush: true);
}
