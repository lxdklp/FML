import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 流式解码并限制单行大小, 无换行的异常输出也不会无限占用内存.
Stream<String> launchLogLines(Stream<List<int>> stream) {
  var pending = '';
  var discard = false;
  // 同步转换器使取消立即传递到管道, 不等待下一段输出.
  return stream
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(
        StreamTransformer<String, String>.fromHandlers(
          handleData: (chunk, sink) {
            final pieces = chunk.split('\n');
            for (var i = 0; i < pieces.length; i++) {
              if (!discard) {
                pending += pieces[i];
                if (pending.length > 65536) {
                  pending = '';
                  discard = true;
                }
              }
              if (i < pieces.length - 1) {
                sink.add(discard ? '[日志行过长, 已省略]' : pending.trimRight());
                pending = '';
                discard = false;
              }
            }
          },
          handleDone: (sink) {
            if (discard) {
              sink.add('[日志行过长, 已省略]');
            } else if (pending.isNotEmpty) {
              sink.add(pending.trimRight());
            }
            sink.close();
          },
        ),
      );
}

class LaunchLogWriter {
  LaunchLogWriter(this.file, {this.maxBytes = 2 * 1024 * 1024});

  final File file;
  final int maxBytes;
  static final _active = <String>{};
  RandomAccessFile? _handle;
  int _size = 0;
  Future<void> _pending = Future.value();
  String? warning;

  Future<void> open() async {
    try {
      await file.parent.create(recursive: true);
      _active.add(file.path);
      _handle = await file.open(mode: FileMode.write);
      // 只清理启动器自己的日志, 正在写入的会话始终保留.
      final logs = await file.parent
          .list(followLinks: false)
          .where(
            (entry) =>
                entry is File &&
                RegExp(r'^launch-\d+-\d+\.log$')
                    .hasMatch(p.basename(entry.path)),
          )
          .cast<File>()
          .toList();
      logs.sort((a, b) => b.path.compareTo(a.path));
      for (final old in logs.skip(5)) {
        if (_active.contains(old.path)) continue;
        await old.delete();
        final previous = File('${old.path}.previous');
        if (await previous.exists()) await previous.delete();
      }
    } on FileSystemException {
      warning = '无法创建或清理启动日志，仍会保留最近的内存日志。';
    }
  }

  Future<void> write(String line) {
    // 标准输出和标准错误共用写入队列, 避免轮转时交叉写入.
    return _pending = _pending.then((_) async {
      if (_handle == null) return;
      try {
        final bytes = utf8.encode('$line\n');
        if (_size + bytes.length > maxBytes && _size > 0) {
          await _handle!.close();
          _handle = null;
          final previous = File('${file.path}.previous');
          if (await previous.exists()) await previous.delete();
          await file.rename(previous.path);
          _handle = await file.open(mode: FileMode.write);
          _size = 0;
        }
        await _handle!.writeFrom(bytes);
        _size += bytes.length;
      } on FileSystemException {
        warning = '日志写入失败，仍会保留最近的内存日志。';
        try {
          await _handle?.close();
        } on FileSystemException {
          /* 关闭失败不影响游戏. */
        }
        _handle = null;
      }
    });
  }

  Future<void> close() async {
    await _pending;
    try {
      await _handle?.close();
    } on FileSystemException {
      warning = '启动日志未能完整写入磁盘。';
    }
    _handle = null;
    _active.remove(file.path);
  }
}

/// 启动前记录文件快照, 只分析本次启动新增或更新的文件.
class LaunchReportCollector {
  LaunchReportCollector(this.instance, {this.gameRoot});

  final String instance;
  final String? gameRoot;
  final Map<String, FileStat> _before = {};
  DateTime _started = DateTime.now();

  Future<List<File>> _candidates() async {
    final result = <File>[];
    for (final dir in {
      instance,
      ?gameRoot,
      p.join(instance, 'crash-reports'),
      p.join(instance, 'logs'),
    }) {
      try {
        await for (final entity in Directory(dir).list(followLinks: false)) {
          if (entity is! File) continue;
          final name = p.basename(entity.path);
          if ((p.basename(dir) == 'crash-reports' && name.endsWith('.txt')) ||
              (p.basename(dir) == 'logs' &&
                  (name == 'latest.log' || name == 'debug.log')) ||
              (name.startsWith('hs_err_pid') && name.endsWith('.log'))) {
            result.add(entity);
          }
        }
      } on FileSystemException {
        /* 不存在或无权限的目录不阻止启动. */
      }
    }
    return result;
  }

  Future<void> snapshot() async {
    _started = DateTime.now();
    for (final file in await _candidates()) {
      _before[file.path] = await file.stat();
    }
  }

  Future<List<File>> changedFiles() async {
    final changed = <(File, DateTime)>[];
    for (final file in await _candidates()) {
      final stat = await file.stat();
      final old = _before[file.path];
      if (stat.type != FileSystemEntityType.file ||
          stat.size == 0 ||
          stat.modified.isBefore(
            _started.subtract(const Duration(seconds: 2)),
          )) {
        continue;
      }
      if (old == null ||
          old.modified != stat.modified ||
          old.changed != stat.changed ||
          old.size != stat.size) {
        changed.add((file, stat.modified));
      }
    }
    changed.sort((a, b) => b.$2.compareTo(a.$2));
    return changed.take(6).map((entry) => entry.$1).toList();
  }

  Stream<String> read(File file) async* {
    // 大文件只取头尾, 保留启动错误和最后的异常堆栈.
    const limit = 512 * 1024;
    final size = await file.length();
    final head = launchLogLines(
      file.openRead(0, size > limit ? limit ~/ 2 : size),
    );
    if (size > limit) {
      final lines = await head.toList();
      // 头部最后一行也可能在凭据中间截断, 整行丢弃.
      yield* Stream.fromIterable(
        lines.take(lines.isEmpty ? 0 : lines.length - 1),
      );
    } else {
      yield* head;
    }
    if (size > limit) {
      yield '[中间日志已省略]';
      // 丢弃从半行开始的第一行, 避免导出被截断的凭据.
      yield* launchLogLines(file.openRead(size - limit ~/ 2)).skip(1);
    }
  }
}
