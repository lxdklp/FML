import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_config.dart';

enum GamePathState { present, missing, inaccessible }

class GameConfigIssue {
  const GameConfigIssue({
    required this.directoryName,
    required this.root,
    required this.checkedPath,
    required this.reason,
    required this.state,
    this.version,
  });
  final String directoryName;
  final String root;
  final String checkedPath;
  final String reason;
  final GamePathState state;
  final String? version;
  bool get canRemove => state == GamePathState.missing;
  String get label =>
      version == null ? directoryName : '$directoryName / $version';
}

/// 仅检查配置引用的路径, 不搜索游戏内容, 不执行磁盘删除.
class GameConfigValidator {
  GameConfigValidator(
    this.config, {
    Future<GamePathState> Function(String, bool)? probe,
  }) : _probe = probe ?? probePath;
  final AppConfig config;
  final Future<GamePathState> Function(String, bool) _probe;

  static Future<GamePathState> probePath(String path, bool directory) async {
    if (path.isEmpty) return GamePathState.missing;
    try {
      // resolveSymbolicLinks 会保留权限错误, 不像 exists 将部分错误折叠为 false.
      final actual = await File(path)
          .resolveSymbolicLinks()
          .timeout(const Duration(seconds: 5));
      final type = await FileSystemEntity.type(actual)
          .timeout(const Duration(seconds: 5));
      final expected = directory
          ? FileSystemEntityType.directory
          : FileSystemEntityType.file;
      return type == expected ? GamePathState.present : GamePathState.missing;
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      final missing = Platform.isWindows
          ? code == 2 || code == 3
          : code == 2 || code == 20;
      return missing ? GamePathState.missing : GamePathState.inaccessible;
    } on TimeoutException {
      return GamePathState.inaccessible;
    } catch (_) {
      return GamePathState.inaccessible;
    }
  }

  Future<GamePathState> _check(String path, bool directory) async {
    try {
      return await _probe(path, directory).timeout(const Duration(seconds: 5));
    } catch (_) {
      return GamePathState.inaccessible;
    }
  }

  static List<String> _list(Map<String, Object> data, String key) =>
      List<String>.from((data[key] as List?) ?? const <String>[]);

  Future<List<GameConfigIssue>> scan() async {
    final data = await config.snapshot();
    final issues = <GameConfigIssue>[];
    for (final name in _list(data, 'PathList').toSet()) {
      final root = data['Path_$name'] as String? ?? '';
      final state = await _check(root, true);
      if (state != GamePathState.present) {
        issues.add(
          GameConfigIssue(
            directoryName: name,
            root: root,
            checkedPath: root,
            state: state,
            reason: state == GamePathState.missing ? '游戏目录不存在' : '无法检查游戏目录',
          ),
        );
        continue;
      }
      for (final version in _list(data, 'Game_$name').toSet()) {
        final directory = p.join(root, 'versions', version);
        final versionState = await _check(directory, true);
        final json = p.join(directory, '$version.json');
        final state = versionState == GamePathState.present
            ? await _check(json, false)
            : versionState;
        if (state == GamePathState.present) continue;
        issues.add(
          GameConfigIssue(
            directoryName: name,
            root: root,
            version: version,
            checkedPath: versionState == GamePathState.present
                ? json
                : directory,
            state: state,
            reason: state == GamePathState.inaccessible
                ? '无法检查版本路径'
                : versionState == GamePathState.missing
                ? '版本目录不存在'
                : '版本描述文件不存在',
          ),
        );
      }
    }
    return issues;
  }

  /// 确认前重新扫描, 仅删除仍然缺失且引用未变化的记录.
  Future<int> removeMissing(Iterable<GameConfigIssue> selected) async {
    final current = await scan();
    final removable = current
        .where(
          (item) =>
              item.canRemove &&
              selected.any(
                (old) =>
                    old.canRemove &&
                    old.directoryName == item.directoryName &&
                    old.root == item.root &&
                    old.version == item.version &&
                    old.checkedPath == item.checkedPath,
              ),
        )
        .toList();
    var count = 0;
    await config.edit((data) {
      final names = _list(data, 'PathList');
      for (final item in removable) {
        final name = item.directoryName;
        if (!names.contains(name) ||
            (data['Path_$name'] as String? ?? '') != item.root) {
          continue;
        }
        final games = _list(data, 'Game_$name');
        final versions = item.version == null ? games : <String>[item.version!];
        if (item.version != null && !games.contains(item.version)) continue;
        // 旧键使用下划线拼接, 避免删除另一组名称恰好组合出的同名键.
        for (final version in versions) {
          final key = 'Config_${name}_$version';
          final shared = names
              .where((other) => other != name)
              .any(
                (other) => _list(
                  data,
                  'Game_$other',
                ).any((game) => 'Config_${other}_$game' == key),
              );
          if (!shared) data.remove(key);
        }
        if (item.version == null) {
          names.remove(name);
          data.remove('Path_$name');
          data.remove('Game_$name');
          if (data['SelectedPath'] == name) {
            data.remove('SelectedPath');
            data.remove('SelectedGame');
          }
        } else {
          games.removeWhere((game) => game == item.version);
          data['Game_$name'] = games;
          if (data['SelectedPath'] == name &&
              data['SelectedGame'] == item.version) {
            data.remove('SelectedGame');
          }
        }
        count++;
      }
      data['PathList'] = names;
    });
    return count;
  }
}
