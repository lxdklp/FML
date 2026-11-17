import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'launch_analysis.dart';
import 'launch_logs.dart';

typedef LaunchProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

enum LaunchState {
  preparing,
  starting,
  running,
  failed,
  crashed,
  exited,
  cancelled,
}

/// 会话由历史记录持有, 不依赖启动页的生命周期.
class LaunchSession extends ChangeNotifier {
  LaunchSession({
    this.startProcess = Process.start,
    this.loader = '',
    this.name = '',
    this.readyDelay = const Duration(seconds: 1),
    this.drainTimeout = const Duration(seconds: 3),
  });

  final LaunchProcessStarter startProcess;
  String? instancePath;
  String loader;
  String name;
  final Duration readyDelay;
  final Duration drainTimeout;
  final DateTime createdAt = DateTime.now();
  DateTime? endedAt;
  DateTime? readyAt;
  LaunchState state = LaunchState.preparing;
  String message = '正在准备启动';
  String? failureDetail;
  final redactor = LaunchRedactor();
  final analyzer = LaunchAnalyzer();
  final Queue<String> _recent = Queue();
  LaunchProgressDetector? _detector;
  LaunchLogWriter? _writer;
  LaunchReportCollector? _reports;
  Process? _process;
  bool _processExited = false;
  bool _stopRequested = false;
  bool _forceStopRequested = false;
  bool _failedBeforeStop = false;
  bool _runStarted = false;
  bool analyzing = false;
  int? exitCode;
  Timer? _readyTimer;
  Timer? _notifyTimer;
  List<String> reportNames = [];
  String? monitorWarning;
  final Set<StreamIterator<String>> _readers = {};

  bool get isActive => _process != null && !_processExited;
  bool get isBusy =>
      state == LaunchState.preparing ||
      state == LaunchState.starting ||
      analyzing;
  bool get hasFailure =>
      state == LaunchState.failed || state == LaunchState.crashed;
  bool get stopRequested => _stopRequested;
  Duration get elapsed => (endedAt ?? DateTime.now()).difference(createdAt);
  Duration get startupElapsed =>
      (readyAt ?? endedAt ?? DateTime.now()).difference(createdAt);
  String? get logPath => _writer?.file.path;
  String? get logWarning => _writer?.warning ?? monitorWarning;
  List<String> get recentLines => List.unmodifiable(_recent);
  List<LaunchDiagnosis> get diagnoses => analyzer.diagnoses;

  void prepare(String text) {
    if (state != LaunchState.preparing || _stopRequested) return;
    message = redactor.clean(text);
    notifyListeners();
  }

  void failPreparation(String error) {
    if (_runStarted || state != LaunchState.preparing) return;
    final safe = redactor.clean(error);
    analyzer.add(safe);
    _remember(safe);
    state = LaunchState.failed;
    message = '启动失败';
    failureDetail = safe;
    endedAt = DateTime.now();
    notifyListeners();
  }

  void cancelPreparation() {
    if (state != LaunchState.preparing) return;
    if (_runStarted) {
      stop();
      return;
    }
    _stopRequested = true;
    state = LaunchState.cancelled;
    message = '已取消启动';
    endedAt = DateTime.now();
    notifyListeners();
  }

  void _remember(String line) {
    // 超长输出仍写入日志, 页面仅保存有限的上下文.
    _recent.add(line.length > 2000 ? '${line.substring(0, 2000)}…' : line);
    while (_recent.length > 200) {
      _recent.removeFirst();
    }
  }

  void _notifySoon() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 250), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  void _fatal() {
    if (_stopRequested && !_failedBeforeStop) return;
    _readyTimer?.cancel();
    state = readyAt == null ? LaunchState.failed : LaunchState.crashed;
    message = readyAt == null ? '启动失败' : (_processExited ? '游戏异常退出' : '游戏发生异常');
  }

  Future<void> _receive(String raw, String source) async {
    final line = redactor.clean(raw);
    _remember('[$source] $line');
    analyzer.add(line);
    if (LaunchAnalyzer.isFatal(line)) {
      _fatal();
    } else if (state == LaunchState.starting &&
        !_processExited &&
        !_stopRequested) {
      final stage = _detector!.accept(line);
      message = switch (stage) {
        LaunchStage.waiting => '启动中，等待游戏响应',
        LaunchStage.initializing => '启动中，正在初始化',
        LaunchStage.mods => '启动中，正在加载模组',
        LaunchStage.graphics => '启动中，正在初始化图形',
        LaunchStage.resources || LaunchStage.ready => '启动中，正在加载资源',
      };
      if (stage == LaunchStage.ready && _readyTimer == null) {
        // 短暂合并相邻输出, 避免同一批日志先报成功再立即报崩溃.
        _readyTimer = Timer(readyDelay, () {
          if (state != LaunchState.starting ||
              _processExited ||
              _stopRequested ||
              analyzer.fatalEvidence != null) {
            return;
          }
          readyAt = DateTime.now();
          state = LaunchState.running;
          message = '游戏启动完成';
          notifyListeners();
        });
      }
    }
    _notifySoon();
    await _writer?.write('[$source] $line');
  }

  Future<void> _read(Stream<List<int>> stream, String source) async {
    final reader = StreamIterator(launchLogLines(stream));
    _readers.add(reader);
    try {
      while (await reader.moveNext()) {
        await _receive(reader.current, source);
      }
    } catch (_) {
      monitorWarning = '部分游戏输出读取失败，诊断信息可能不完整。';
      _notifySoon();
    } finally {
      _readers.remove(reader);
      await reader.cancel();
    }
  }

  Future<void> run({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    required String gameRoot,
    required String metadataPath,
    Iterable<String> secrets = const [],
  }) async {
    if (_runStarted || state != LaunchState.preparing) return;
    instancePath = p.normalize(p.absolute(workingDirectory));
    if (LaunchHistory.instance.sessions.any(
      (other) =>
          other != this &&
          other.instancePath == instancePath &&
          (other.isActive || other.isBusy),
    )) {
      failPreparation('该版本已有启动或运行中的游戏，请先结束现有进程');
      return;
    }
    _runStarted = true;
    redactor.addSecrets(secrets);
    String? minecraftVersion;
    try {
      final metadata = jsonDecode(await File(metadataPath).readAsString());
      if (metadata is Map && metadata['id'] is String) {
        minecraftVersion = metadata['id'];
      }
    } catch (_) {
      /* 元数据缺失时不启用旧版本兼容规则. */
    }
    if (_stopRequested) {
      await _cancelBeforeProcess();
      return;
    }
    _detector = LaunchProgressDetector(
      loader: loader,
      minecraftVersion: minecraftVersion,
    );
    _reports = LaunchReportCollector(workingDirectory, gameRoot: gameRoot);
    await _reports!.snapshot();
    if (_stopRequested) {
      await _cancelBeforeProcess();
      return;
    }
    _writer = LaunchLogWriter(
      File(
        p.join(
          workingDirectory,
          'fml-launch-logs',
          'launch-${createdAt.microsecondsSinceEpoch}-$pid.log',
        ),
      ),
    );
    await _writer!.open();
    await _writer!.write(
      redactor.clean(
        '版本: $name\n加载器: $loader\nJava: $executable\n启动时间: ${createdAt.toIso8601String()}',
      ),
    );
    if (_stopRequested) {
      await _cancelBeforeProcess();
      return;
    }
    state = LaunchState.starting;
    message = '启动中，等待游戏响应';
    notifyListeners();
    if (_stopRequested) {
      await _cancelBeforeProcess();
      return;
    }
    try {
      _process = await startProcess(
        executable,
        arguments,
        workingDirectory: workingDirectory,
      );
    } catch (error) {
      if (_stopRequested) {
        await _cancelBeforeProcess();
        return;
      }
      // ProcessException 的字符串可能包含完整参数, 只保留系统错误消息.
      final detail = error is ProcessException
          ? '${error.message} (系统错误 ${error.errorCode})'
          : '无法创建游戏进程';
      final safe = redactor.clean(detail);
      analyzer.add(safe);
      _remember(safe);
      await _writer!.write(safe);
      state = LaunchState.failed;
      message = '无法启动 Java：$safe';
      endedAt = DateTime.now();
      await _writer!.close();
      notifyListeners();
      return;
    }
    // 创建进程的异步调用不能中止, 返回句柄后立即执行已请求的取消.
    if (_stopRequested) stop(force: _forceStopRequested);
    notifyListeners();
    final output = _read(_process!.stdout, 'stdout');
    final errors = _read(_process!.stderr, 'stderr');
    exitCode = await _process!.exitCode;
    _processExited = true;
    _readyTimer?.cancel();
    // 进程退出不代表管道已经读完, 必须消费尾部错误后再判定结果.
    await Future.wait([output, errors]).timeout(
      drainTimeout,
      onTimeout: () async {
        // 子进程继承管道后可能保持句柄打开, 不能永久卡在退出处理中.
        monitorWarning = '进程退出后日志管道未关闭，部分尾部输出可能缺失。';
        await Future.wait(_readers.toList().map((reader) => reader.cancel()));
        return Future.wait([output, errors]);
      },
    );
    analyzing = !_stopRequested || _failedBeforeStop;
    if (analyzing) message = '游戏进程已退出，正在检查日志';
    notifyListeners();
    if (analyzing) await _collectReports();
    if (_stopRequested && !_failedBeforeStop) {
      state = LaunchState.cancelled;
      message = '已结束游戏';
    } else if (exitCode != 0 ||
        analyzer.fatalEvidence != null ||
        _failedBeforeStop) {
      _fatal();
    } else {
      state = LaunchState.exited;
      message = readyAt == null ? '游戏已退出，未确认启动完成' : '游戏已退出';
    }
    endedAt = DateTime.now();
    analyzing = false;
    await _writer!.write('结果: $message, 退出码: $exitCode');
    if (hasFailure) await _writer!.write(diagnosticText);
    await _writer!.close();
    _notifyTimer?.cancel();
    _notifyTimer = null;
    notifyListeners();
  }

  Future<void> _cancelBeforeProcess() async {
    await _writer?.write('已取消启动, 未创建游戏进程');
    await _writer?.close();
    state = LaunchState.cancelled;
    message = '已取消启动';
    endedAt = DateTime.now();
    notifyListeners();
  }

  Future<void> _collectReports() async {
    try {
      for (final file in await _reports!.changedFiles()) {
        reportNames.add(p.basename(file.path));
        try {
          await for (final line in _reports!.read(file)) {
            analyzer.add(redactor.clean(line));
          }
        } on FileSystemException {
          monitorWarning = '部分报告无法读取，诊断信息可能不完整。';
        }
      }
    } on FileSystemException {
      monitorWarning = '无法收集游戏报告，已使用进程输出分析。';
    }
  }

  bool stop({bool force = false}) {
    if (!isActive) {
      if (endedAt != null || _processExited) return false;
      if (!_runStarted && state == LaunchState.preparing) {
        cancelPreparation();
        return true;
      }
      if (_runStarted) {
        _stopRequested = true;
        _forceStopRequested = _forceStopRequested || force;
        message = '正在取消启动';
        notifyListeners();
        return true;
      }
      return false;
    }
    final accepted = _process!.kill(
      force ? ProcessSignal.sigkill : ProcessSignal.sigterm,
    );
    if (accepted) {
      _failedBeforeStop = _failedBeforeStop || hasFailure;
      _stopRequested = true;
      _readyTimer?.cancel();
      message = '正在结束游戏';
      notifyListeners();
    } else if (_stopRequested) {
      message = '未能结束游戏，请重试或强制结束';
      notifyListeners();
    }
    return accepted;
  }

  String get diagnosticText => redactor.clean(
    [
      '版本: $name',
      '加载器: $loader',
      '状态: $message',
      if (exitCode != null) '退出码: $exitCode',
      if (hasFailure && diagnoses.isEmpty) '暂未识别具体原因，请查看下方日志。',
      for (final result in diagnoses)
        '${result.certain ? "检测结果" : "可能原因"}: ${result.title}\n建议: ${result.advice}\n证据:\n${result.evidence}',
      if (analyzer.fatalEvidence != null) '异常标记: ${analyzer.fatalEvidence}',
      if (reportNames.isNotEmpty) '本次报告: ${reportNames.join(", ")}',
      if (logPath != null) '启动日志: $logPath',
      ?logWarning,
      '最近输出:',
      ..._recent,
    ].join('\n\n'),
  );
}

class LaunchHistory extends ChangeNotifier {
  LaunchHistory._();
  static final instance = LaunchHistory._();
  final List<LaunchSession> _sessions = [];
  List<LaunchSession> get sessions => List.unmodifiable(_sessions.reversed);

  void add(LaunchSession session) {
    _sessions.add(session);
    session.addListener(_changed);
    _changed();
  }

  void _changed() {
    final finished = _sessions
        .where((session) => !session.isActive && !session.isBusy)
        .toList();
    for (final old in finished.take(
      finished.length > 5 ? finished.length - 5 : 0,
    )) {
      old.removeListener(_changed);
      _sessions.remove(old);
    }
    notifyListeners();
  }
}
