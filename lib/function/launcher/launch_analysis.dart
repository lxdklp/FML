import 'dart:collection';

class LaunchDiagnosis {
  const LaunchDiagnosis(
    this.title,
    this.advice,
    this.evidence, {
    this.certain = true,
  });

  final String title;
  final String advice;
  final String evidence;
  final bool certain;
}

class LaunchRedactor {
  final Set<String> _secrets = {};

  void addSecrets(Iterable<String> values) {
    _secrets.addAll(values.where((value) => value.isNotEmpty && value != '0'));
  }

  void addAccount(String type, List<String> account) {
    if (type == '1' && account.length > 2) addSecrets([account[2]]);
    if (type == '2' && account.length > 6) {
      addSecrets([account[4], account[5], account[6]]);
    }
  }

  String clean(String text) {
    var result = text.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
    // 先替换完整凭据, 避免短凭据破坏长凭据的匹配.
    final secrets = _secrets.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final secret in secrets) {
      result = result.replaceAll(secret, '[已隐藏]');
    }
    result = result.replaceAllMapped(
      RegExp(
        r'''((?:--)?(?:access[_-]?token|refresh[_-]?token|client[_-]?token|password|authorization)\b["']?\s*(?:[:=]\s*|\s+))(?:Bearer\s+)?(?:"[^"]*"|'[^']*'|[^\s,}\]]+)''',
        caseSensitive: false,
      ),
      (match) => '${match[1]}[已隐藏]',
    );
    return result.replaceAllMapped(
      RegExp(r'(https?://)[^\s/@:]+:[^\s/@]+@', caseSensitive: false),
      (match) => '${match[1]}[已隐藏]@',
    );
  }
}

class _Rule {
  _Rule(this.id, String pattern, this.title, this.advice, {this.certain = true})
    : pattern = RegExp(pattern, caseSensitive: false);

  final String id;
  final RegExp pattern;
  final String title;
  final String advice;
  final bool certain;
}

/// 只根据明确的日志特征生成建议, 堆栈关联不等同于根因.
class LaunchAnalyzer {
  final LinkedHashMap<String, LaunchDiagnosis> _matches = LinkedHashMap();
  final Queue<String> _context = Queue();
  final Map<String, int> _following = {};
  String? fatalEvidence;

  static final _rules = [
    _Rule(
      'java',
      r'UnsupportedClassVersionError|Unsupported class file major version|Unsupported major.minor version|compiled by a more recent version|InaccessibleObjectException|module java.base does not (?:export|open)',
      'Java 或字节码版本不兼容',
      '按游戏及模组要求选择 Java；若错误来自 ASM 或加载器，还需要检查加载器版本。',
    ),
    _Rule(
      'heap',
      r'Could not reserve enough space|Invalid maximum heap size|Too small maximum heap|Could not allocate metaspace',
      'JVM 无法分配指定内存',
      '检查内存设置是否过大或过小、系统剩余内存及 Java 是否为合适的 64 位版本。',
    ),
    _Rule(
      'memory',
      r'OutOfMemoryError|Out of Memory Error|out of physical RAM or swap space|Native memory allocation .* failed',
      '内存不足',
      '关闭占用内存的程序，并结合系统可用内存调整游戏内存；原生内存不足时不应继续增大堆内存。',
    ),
    _Rule(
      'arguments',
      r'Unrecognized (?:VM )?option|Improperly specified VM option|Unrecognized VM option',
      'Java 启动参数不受支持',
      '检查自定义 JVM 参数，并确认参数适用于当前 Java 版本。',
    ),
    _Rule(
      'graphics',
      r'driver does not appear to support OpenGL|GLFW error 6554[23]|Failed to create (?:the )?(?:GLFW )?window|Couldn.t set pixel format|Pixel format not accelerated|No OpenGL context',
      '图形环境初始化失败',
      '检查显卡驱动、OpenGL 支持及远程桌面环境；根据日志确认是否需要更新驱动。',
    ),
    _Rule(
      'native',
      r'UnsatisfiedLinkError|wrong ELF class|incompatible architecture|not a valid Win32 application|Can.t load (?:AMD 64-bit|IA 32-bit)',
      '原生库加载失败或架构不匹配',
      '检查 Java、系统及原生库的架构是否一致，并检查原生库是否缺失。',
    ),
    _Rule(
      'duplicate',
      r'DuplicateModsFoundException|Found (?:a )?duplicate mods?|ModResolutionException: Duplicate',
      '发现重复模组',
      '根据日志中的模组 ID 或文件名，移除重复版本后重试。',
    ),
    _Rule(
      'dependencies',
      r'Incompatible mods found|Missing or unsupported mandatory dependencies|Could not find required mod|requires .* which is missing|ModResolutionException|Mod .* requires|MissingModsException',
      '模组依赖或版本不匹配',
      '查看日志列出的模组及版本要求，补齐前置模组或更换兼容版本。',
    ),
    _Rule(
      'config',
      r'Failed loading config file|nightconfig.*ParsingException',
      '模组配置读取失败',
      '根据日志定位配置文件，备份后检查格式，或让对应模组重新生成配置。',
    ),
    _Rule(
      'mixin',
      r'MixinApplyError|MixinTransformerError|Mixin apply .* failed|InvalidMixinException|InjectionError',
      'Mixin 注入失败，可能存在模组冲突',
      '检查日志中的模组和 Mixin 名称及版本兼容性；堆栈中出现的模组不一定是唯一原因。',
      certain: false,
    ),
    _Rule(
      'files',
      r'Could not find or load main class|ClassNotFoundException|NoClassDefFoundError|Unable to access jarfile|zip END header not found|Invalid or corrupt jarfile|缺少运行库',
      '类或依赖文件缺失、损坏或不兼容',
      '检查游戏及加载器安装完整性；若涉及模组类名，先检查模组依赖和版本。',
      certain: false,
    ),
    _Rule(
      'permission',
      r'AccessDeniedException|Permission denied|Access is denied|拒绝访问',
      '文件访问被拒绝',
      '检查日志中的文件路径、目录写入权限及安全软件拦截记录。',
    ),
    _Rule(
      'auth',
      r'Invalid (?:access )?token|Invalid session|Failed to (?:verify|authenticate)|AuthenticationException|登录失败|令牌刷新失败|重新登录',
      '账号认证失败',
      '检查网络及认证服务状态，然后重新登录账号。',
    ),
  ];

  static bool isChat(String line) =>
      RegExp(r'\[CHAT\]', caseSensitive: false).hasMatch(line);

  static bool isFatal(String line) =>
      !isChat(line) &&
      RegExp(
        r'Crash report saved to|This crash report has been saved to:|Could not save crash report to|#@!@# Game crashed|^---- Minecraft Crash Report ----|/ERROR\]: Unable to launch|An exception was thrown, the game will display an error screen and halt\.|A fatal error has been detected by the Java Runtime Environment|Could not create the Java Virtual Machine\.|Error occurred during initialization of VM',
        caseSensitive: false,
      ).hasMatch(line);

  void add(String line) {
    if (isChat(line)) return;
    final excerpt = line.length > 2000 ? '${line.substring(0, 2000)}…' : line;
    if (isFatal(line)) fatalEvidence ??= excerpt;
    for (final id in _following.keys.toList()) {
      final previous = _matches[id]!;
      if (_following[id]! > 0 && previous.evidence.length < 8000) {
        _matches[id] = LaunchDiagnosis(
          previous.title,
          previous.advice,
          '${previous.evidence}\n$excerpt',
          certain: previous.certain,
        );
        _following[id] = _following[id]! - 1;
      }
    }
    _context.add(excerpt);
    while (_context.length > 6) {
      _context.removeFirst();
    }
    for (final rule in _rules) {
      if (_matches.containsKey(rule.id) || !rule.pattern.hasMatch(line)) {
        continue;
      }
      _matches[rule.id] = LaunchDiagnosis(
        rule.title,
        rule.advice,
        _context.join('\n'),
        certain: rule.certain,
      );
      _following[rule.id] = 6;
    }
  }

  List<LaunchDiagnosis> get diagnoses => List.unmodifiable([
    ..._matches.values.where((result) => result.certain),
    ..._matches.values.where((result) => !result.certain),
  ]);
}

enum LaunchStage { waiting, initializing, mods, graphics, resources, ready }

/// 参考常见客户端日志, 不将图形初始化等同于现代版本加载完成.
class LaunchProgressDetector {
  LaunchProgressDetector({required this.loader, this.minecraftVersion});

  final String loader;
  final String? minecraftVersion;
  LaunchStage stage = LaunchStage.waiting;

  LaunchStage accept(String line) {
    if (LaunchAnalyzer.isChat(line)) return stage;
    final text = line.toLowerCase();
    var next = LaunchStage.initializing;
    if (text.contains('loading minecraft') ||
        text.contains('loading mods') ||
        text.contains('modlauncher running')) {
      next = LaunchStage.mods;
    }
    if (text.contains('lwjgl version') ||
        text.contains('backend library:') ||
        text.contains('opengl renderer:')) {
      next = LaunchStage.graphics;
    }
    if (text.contains('openal initialized') ||
        text.contains('starting up soundsystem') ||
        text.contains('reloading resourcemanager')) {
      next = LaunchStage.resources;
    }
    if (RegExp(r'created:?.*textures.*-atlas').hasMatch(text) ||
        text.contains('found animation info')) {
      next = LaunchStage.ready;
    }
    // 早期原版没有现代纹理日志, 仅对已知旧版本使用音频信号兼容.
    final oldVersion = RegExp(r'^1\.([0-5])(?:\.\d+)?$')
        .hasMatch(minecraftVersion ?? '');
    if (loader == 'Vanilla' &&
        oldVersion &&
        (text.contains('lwjgl openal') ||
            text.contains('sound engine started'))) {
      next = LaunchStage.ready;
    }
    if (next.index > stage.index) stage = next;
    return stage;
  }
}
