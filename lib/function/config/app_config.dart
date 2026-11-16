import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_location.dart';

/// 业务代码仅通过此入口读写配置, 后端和键前缀均由内部处理
class AppConfig {
  AppConfig._(
    this._store, {
    required this.canExportPortable,
    required this.storageDescription,
    this.location,
  });

  static AppConfig? _instance;
  static Future<void>? _initialization;
  static AppConfig get instance => _instance ?? (throw StateError('配置尚未初始化'));
  static Future<AppConfig> getInstance() async => instance;

  final _ConfigStore _store;
  final bool canExportPortable;
  final String storageDescription;
  final AppLocation? location;
  Future<void> _pending = Future.value();
  final _changes = StreamController<Set<String>>.broadcast();
  Stream<Set<String>> get changes => _changes.stream;

  static Future<void> initialize() => _initialization ??= _initialize();

  static Future<void> _initialize() async {
    final location = AppLocation.detect();
    _instance = await open(location);
  }

  /// 注入系统后端和目录探测函数, 便于验证模式隔离
  static Future<AppConfig> open(
    AppLocation location, {
    SharedPreferencesAsync? systemPreferences,
    Future<bool> Function(String)? directoryWritable,
  }) async {
    final canInspect =
        location.platform != 'macos' ||
        await (directoryWritable ?? _directoryWritable)(location.root);
    if (canInspect) {
      final file = File(location.configPath);
      var exists = true;
      try {
        await file.resolveSymbolicLinks();
      } on FileSystemException catch (error) {
        final code = error.osError?.errorCode;
        final missing = Platform.isWindows
            ? code == 2 || code == 3
            : code == 2 || code == 20;
        if (!missing) rethrow;
        // 断开的配置链接属于配置错误, 不应切换到系统配置.
        if (await FileSystemEntity.type(file.path, followLinks: false) ==
            FileSystemEntityType.link) {
          rethrow;
        }
        exists = false;
      }
      if (exists) {
        if (await FileSystemEntity.type(file.path) !=
            FileSystemEntityType.file) {
          throw FileSystemException('便携配置不是文件', file.path);
        }
        return portable(file, location: location);
      }
      // 替换中断后仍识别为便携模式, 不意外读取系统配置.
      if (await File('${location.configPath}.bak').exists()) {
        throw FileSystemException(
          '便携配置缺失, 请从 settings.json.bak 恢复',
          location.configPath,
        );
      }
    }
    final description = systemPreferences != null
        ? '系统配置 (测试后端)'
        : location.platform == 'macos'
        ? 'NSUserDefaults: ${(await PackageInfo.fromPlatform()).packageName}'
        : p.join(
            (await getApplicationSupportDirectory()).path,
            'shared_preferences.json',
          );
    return system(
      preferences: systemPreferences,
      location: location,
      storageDescription: description,
    );
  }

  static AppConfig system({
    SharedPreferencesAsync? preferences,
    AppLocation? location,
    String? storageDescription,
  }) => AppConfig._(
    _SystemConfigStore(preferences ?? SharedPreferencesAsync()),
    canExportPortable: true,
    storageDescription:
        storageDescription ??
        '系统配置 (${Platform.isMacOS ? 'NSUserDefaults' : '应用数据目录'})',
    location: location,
  );

  static Future<AppConfig> portable(File file, {AppLocation? location}) async =>
      AppConfig._(
        await _FileConfigStore.open(file),
        canExportPortable: false,
        storageDescription: file.path,
        location: location,
      );

  static Future<bool> _directoryWritable(String directory) async {
    Directory? probe;
    try {
      // 创建独立临时目录检测实际写权限, 不依赖权限位推断 ACL.
      await Directory(directory).list().take(1).drain<void>();
      probe = await Directory(directory).createTemp('.fml-write-check-');
      return true;
    } on FileSystemException {
      return false;
    } finally {
      if (probe != null) await probe.delete();
    }
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<Map<String, Object>> snapshot() => _serial(_store.read);
  Future<Object?> get(String key) => _serial(() => _store.readValue(key));
  Future<String?> getString(String key) async => await get(key) as String?;
  Future<bool?> getBool(String key) async => await get(key) as bool?;
  Future<int?> getInt(String key) async => await get(key) as int?;
  Future<double?> getDouble(String key) async => await get(key) as double?;
  Future<List<String>?> getStringList(String key) async {
    final value = await get(key);
    return value == null ? null : List<String>.from(value as List);
  }

  Future<Set<String>> getKeys() async => (await snapshot()).keys.toSet();
  Future<bool> containsKey(String key) async =>
      (await snapshot()).containsKey(key);

  Future<void> setString(String key, String value) => _set(key, value);
  Future<void> setBool(String key, bool value) => _set(key, value);
  Future<void> setInt(String key, int value) => _set(key, value);
  Future<void> setDouble(String key, double value) => _set(key, value);
  Future<void> setStringList(String key, List<String> value) =>
      _set(key, List<String>.of(value));
  Future<void> _set(String key, Object value) => edit((data) {
    data[key] = value;
  });
  Future<void> remove(String key) => edit((data) {
    data.remove(key);
  });
  Future<void> clear() => edit((data) => data.clear());

  /// 回调只修改当前快照
  Future<void> edit(void Function(Map<String, Object> data) change) =>
      _serial(() async {
        final before = await _store.read();
        final after = _copy(before);
        change(after);
        _validate(after);
        await _store.write(before, after);
        final changed = {...before.keys, ...after.keys}
            .where((key) => jsonEncode(before[key]) != jsonEncode(after[key]))
            .toSet();
        if (changed.isNotEmpty) _changes.add(changed);
      });

  Future<void> updateStringList(
    String key,
    List<String> Function(List<String> current) update,
  ) => edit((data) {
    data[key] = List<String>.of(
      update(List<String>.from((data[key] as List?) ?? const <String>[])),
    );
  });

  Future<void> close() => _serial(() async {
    await _store.close();
    await _changes.close();
  });

  static Map<String, Object> _copy(Map<String, Object> input) => input.map(
    (key, value) =>
        MapEntry(key, value is List ? List<String>.from(value) : value),
  );

  static void _validate(Map<String, Object> input) {
    for (final entry in input.entries) {
      final value = entry.value;
      if (!(value is String ||
          value is bool ||
          value is int ||
          value is double && value.isFinite ||
          value is List && value.every((item) => item is String))) {
        throw FormatException('不支持的配置类型: ${entry.key}');
      }
    }
  }
}

abstract class _ConfigStore {
  Future<Map<String, Object>> read();
  Future<Object?> readValue(String key);
  Future<void> write(Map<String, Object> before, Map<String, Object> after);
  Future<void> close() async {}
}

class _SystemConfigStore extends _ConfigStore {
  _SystemConfigStore(this.preferences);
  final SharedPreferencesAsync preferences;
  static const prefix = 'flutter.';

  @override
  Future<Map<String, Object>> read() async {
    final keys = (await preferences.getKeys())
        .where((key) => key.startsWith(prefix))
        .toSet();
    final values = await preferences.getAll(allowList: keys);
    return AppConfig._copy({
      for (final entry in values.entries)
        if (entry.value != null)
          entry.key.substring(prefix.length): entry.value!,
    });
  }

  @override
  Future<Object?> readValue(String key) async {
    final raw = '$prefix$key';
    final value = (await preferences.getAll(allowList: {raw}))[raw];
    return value is List ? List<String>.from(value) : value;
  }

  @override
  Future<void> write(
    Map<String, Object> before,
    Map<String, Object> after,
  ) async {
    for (final key in before.keys.where((key) => !after.containsKey(key))) {
      await preferences.remove('$prefix$key');
    }
    for (final entry in after.entries) {
      if (jsonEncode(before[entry.key]) == jsonEncode(entry.value)) continue;
      final key = '$prefix${entry.key}';
      switch (entry.value) {
        case String value:
          await preferences.setString(key, value);
        case bool value:
          await preferences.setBool(key, value);
        case int value:
          await preferences.setInt(key, value);
        case double value:
          await preferences.setDouble(key, value);
        case List value:
          await preferences.setStringList(key, value.cast<String>());
      }
    }
  }
}

class _FileConfigStore extends _ConfigStore {
  _FileConfigStore(this.file, this.lock, this._data);
  final File file;
  final RandomAccessFile lock;
  Map<String, Object> _data;
  static final Set<String> _openFiles = {};
  bool _closed = false;

  static Future<_FileConfigStore> open(File file) async {
    final path = await file.resolveSymbolicLinks();
    if (!_openFiles.add(path)) throw StateError('此便携配置已被打开');
    RandomAccessFile? lock;
    try {
      lock = await File('$path.lock').open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('配置必须是 JSON 对象');
      }
      final data = Map<String, Object>.from(raw);
      AppConfig._validate(data);
      // 验证配置本身和所在目录均可写
      final writable = await file.open(mode: FileMode.append);
      await writable.close();
      final probe = await file.parent.createTemp('.fml-config-check-');
      await probe.delete();
      return _FileConfigStore(File(path), lock, AppConfig._copy(data));
    } catch (_) {
      await lock?.close();
      _openFiles.remove(path);
      rethrow;
    }
  }

  Future<void> _ensureOpen() async {
    if (_closed) throw StateError('配置已关闭');
    // 使用锁句柄防止 AOT 将仅用于关闭的字段裁剪后提前回收句柄
    await lock.position();
  }

  @override
  Future<Map<String, Object>> read() async {
    await _ensureOpen();
    return AppConfig._copy(_data);
  }

  @override
  Future<Object?> readValue(String key) async {
    await _ensureOpen();
    final value = _data[key];
    return value is List ? List<String>.from(value) : value;
  }

  @override
  Future<void> write(
    Map<String, Object> before,
    Map<String, Object> after,
  ) async {
    await _ensureOpen();
    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await temporary.writeAsString(jsonEncode(after), flush: true);
    await file.copy(backup.path);
    try {
      // Windows 不支持用 rename 覆盖已存在文件
      if (Platform.isWindows) await file.delete();
      await temporary.rename(file.path);
    } catch (_) {
      if (!await file.exists()) await backup.copy(file.path);
      rethrow;
    }
    _data = AppConfig._copy(after);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await lock.close();
    _openFiles.remove(file.path);
  }
}
