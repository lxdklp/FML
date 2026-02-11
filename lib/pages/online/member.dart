import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_gbk2utf8/flutter_gbk2utf8.dart';
import 'package:fml/function/log.dart';
import 'package:fml/function/online/scaffolding/client.dart';
import 'package:fml/function/online/fakeserver.dart';

class EasyTierPeer {
  final String? ipv4;
  final String hostname;
  final String cost;
  final String latency;
  final String loss;
  final String rx;
  final String tx;
  final String tunnel;
  final String nat;
  final String version;
  final String id;
  final String? playerName;
  final String? playerVendor;
  final String? playerKind;

  EasyTierPeer({
    this.ipv4,
    required this.hostname,
    required this.cost,
    required this.latency,
    required this.loss,
    required this.rx,
    required this.tx,
    required this.tunnel,
    required this.nat,
    required this.version,
    required this.id,
    this.playerName,
    this.playerVendor,
    this.playerKind,
  });
}

class MemberPage extends StatefulWidget {
  final String etServer;
  const MemberPage({super.key, required this.etServer});

  static bool _persistIsConnected = false;
  static bool _persistIsEasyTierRunning = false;
  static Process? _persistEasyTierProcess;
  static String? _persistNetworkName;
  static String? _persistNetworkKey;
  static OnlineCenterClient? _persistClient;
  static List<PlayerProfile> _persistPlayers = [];
  static int? _persistMinecraftServerPort;
  static String? _persistIpAddress;
  static FakeServer? _persistFakeServer;
  static List<EasyTierPeer> _persistPeers = [];

  @override
  MemberPageState createState() => MemberPageState();
}

class MemberPageState extends State<MemberPage> {
  final TextEditingController _codeController = TextEditingController();
  bool _isValidCode = false;
  bool _isConnecting = false;
  bool _isEasyTierRunning = false;
  bool _isConnected = false;
  Process? _easyTierProcess;
  String? _machineId;
  String? _playerName;
  String? _networkName;
  String? _networkKey;
  OnlineCenterClient? _client;
  List<PlayerProfile> _players = [];
  int? _minecraftServerPort;
  String? _ipAddress;
  Timer? _minecraftLaunchTimer;
  FakeServer? _fakeServer;
  List<EasyTierPeer> _peers = [];
  List<EasyTierPeer> _servers = [];
  Timer? _playerListRefreshTimer;
  Timer? _peerListRefreshTimer;
  final Random _random = Random();
  String? mcPort;

  @override
  void initState() {
    super.initState();
    _loadPlayerName();
    _initMachineId();
    _codeController.addListener(_validateCode);
    _restoreConnectionState();

    // 玩家列表刷新定时器
    _playerListRefreshTimer = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) {
      if (_isConnected && _client != null && mounted) {
        setState(() {});
      }
    });
    // 节点列表刷新定时器
    _peerListRefreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isEasyTierRunning && mounted) {
        _refreshPeerList();
      }
    });
  }

  // 从静态变量恢复状态
  Future<void> _restoreConnectionState() async {
    _isConnected = MemberPage._persistIsConnected;
    _isEasyTierRunning = MemberPage._persistIsEasyTierRunning;
    _easyTierProcess = MemberPage._persistEasyTierProcess;
    _networkName = MemberPage._persistNetworkName;
    _networkKey = MemberPage._persistNetworkKey;
    _client = MemberPage._persistClient;
    _players = MemberPage._persistPlayers;
    _minecraftServerPort = MemberPage._persistMinecraftServerPort;
    _ipAddress = MemberPage._persistIpAddress;
    _fakeServer = MemberPage._persistFakeServer;
    _peers = MemberPage._persistPeers;
    if (_isConnected && _client != null) {
      _setupClientListeners();
    }
    LogUtil.log(
      '恢复连接状态: isConnected=$_isConnected, isEasyTierRunning=$_isEasyTierRunning',
      level: 'INFO',
    );
    if (_networkName != null && _networkKey != null && !_isConnected) {
      final networkParts = _networkName!
          .substring('scaffolding-mc-'.length)
          .split('-');
      final codePrefix = 'U/${networkParts[0]}-${networkParts[1]}';
      final codeSuffix = _networkKey!;
      _codeController.text = '$codePrefix-$codeSuffix';
    }
  }

  // 启动FakeServer
  Future<void> _startFakeServer() async {
    if (_fakeServer != null && _fakeServer!.isRunning) {
      LogUtil.log('FakeServer已在运行', level: 'INFO');
      return;
    }
    if (_minecraftServerPort == null || _ipAddress == null) {
      LogUtil.log('无法启动FakeServer: 缺少服务器信息', level: 'WARNING');
      return;
    }
    try {
      int fakeServerPort = await _findAvailablePort();
      LogUtil.log('使用随机端口 $fakeServerPort 启动FakeServer', level: 'INFO');
      _fakeServer = FakeServer(port: fakeServerPort);
      await _fakeServer!.start();
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('SelectedPath') ?? '';
      final path = prefs.getString('Path_$name') ?? '';
      final String cliPath =
          ('$path${Platform.pathSeparator}easytier${Platform.pathSeparator}easytier-cli');
      LogUtil.log(
        '正在转发Minecraft端口: $_ipAddress:$_minecraftServerPort 到 0.0.0.0:$fakeServerPort',
        level: 'INFO',
      );
      await Process.run(
        cliPath,
        'port-forward add tcp 0.0.0.0:$fakeServerPort $_ipAddress:$_minecraftServerPort'
            .split(' '),
      );
      MemberPage._persistFakeServer = _fakeServer;
      LogUtil.log('FakeServer已启动在端口 $fakeServerPort', level: 'INFO');
      setState(() {
        mcPort = fakeServerPort.toString();
      });
    } catch (e) {
      LogUtil.log('启动FakeServer失败: $e', level: 'ERROR');
      _fakeServer = null;
      MemberPage._persistFakeServer = null;
    }
  }

  // 停止FakeServer
  Future<void> _stopFakeServer() async {
    if (_fakeServer != null) {
      await _fakeServer!.stop();
      _fakeServer = null;
      MemberPage._persistFakeServer = null;
      LogUtil.log('FakeServer已停止', level: 'INFO');
    }
  }

  // 设置Minecraft端口转发
  Future<void> _setupMinecraftPortForwarding() async {
    if (_minecraftServerPort == null || _ipAddress == null) {
      LogUtil.log(
        '无法设置Minecraft端口转发: 缺少服务器信息 (端口: $_minecraftServerPort, IP: $_ipAddress)',
        level: 'WARNING',
      );
      return;
    }
    if (_fakeServer != null && _fakeServer!.isRunning) {
      LogUtil.log('FakeServer已在运行, 跳过重复启动', level: 'INFO');
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('SelectedPath') ?? '';
      final path = prefs.getString('Path_$name') ?? '';
      final String cliPath =
          ('$path${Platform.pathSeparator}easytier${Platform.pathSeparator}easytier-cli');
      int mcLocalPort = await _findAvailablePort();
      LogUtil.log(
        '正在转发Minecraft端口: $_ipAddress:$_minecraftServerPort 到 127.0.0.1:$mcLocalPort',
        level: 'INFO',
      );
      await Process.run(
        cliPath,
        'port-forward add tcp 127.0.0.1:$mcLocalPort $_ipAddress:$_minecraftServerPort'
            .split(' '),
      );
      await _startFakeServer();
    } catch (e) {
      LogUtil.log('设置Minecraft端口转发失败: $e', level: 'ERROR');
    }
  }

  // 客户端监听器
  Future<void> _setupClientListeners() async {
    _client!.playersStream.listen((players) {
      if (mounted) {
        setState(() {
          _players = players;
          MemberPage._persistPlayers = players;
        });
      }
    });
    _client!.minecraftPortStream.listen((port) {
      if (!mounted) return;
      if (port != null && port > 0) {
        LogUtil.log('收到Minecraft服务器端口: $port', level: 'INFO');
        setState(() {
          _minecraftServerPort = port;
          MemberPage._persistMinecraftServerPort = port;
        });
        _setupMinecraftPortForwarding();
      } else if (port == null) {
        LogUtil.log('服务器明确返回:Minecraft服务未启动', level: 'WARNING');
        setState(() {
          _minecraftServerPort = null;
          MemberPage._persistMinecraftServerPort = null;
        });
      }
    });
    // 监听服务器断开事件
    _client!.serverDisconnectedStream.listen((disconnected) {
      if (disconnected && mounted) {
        LogUtil.log('检测到服务器已断开', level: 'ERROR');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('服务器已关闭或网络连接中断'),
            duration: Duration(seconds: 5),
          ),
        );
        _disconnect();
      }
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _minecraftLaunchTimer?.cancel();
    _playerListRefreshTimer?.cancel();
    _peerListRefreshTimer?.cancel();
    super.dispose();
  }

  // 加载玩家名称
  Future<void> _loadPlayerName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('SelectedAccountName');
      if (name != null && name.isNotEmpty) {
        setState(() {
          _playerName = name;
        });
      } else {
        setState(() {
          _playerName = "匿名玩家";
        });
      }
    } catch (e) {
      LogUtil.log('加载玩家名称失败: $e', level: 'ERROR');
      setState(() {
        _playerName = "FML客户端";
      });
    }
  }

  // 初始化机器ID
  Future<void> _initMachineId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var machineId = prefs.getString('machine_id');
      if (machineId == null) {
        machineId = const Uuid().v4();
        await prefs.setString('machine_id', machineId);
      }
      setState(() {
        _machineId = machineId;
      });
    } catch (e) {
      final tempId = const Uuid().v4();
      setState(() {
        _machineId = tempId;
      });
      LogUtil.log('生成临时机器ID: $_machineId', level: 'ERROR');
    }
  }

  // 验证输入的房间码
  Future<void> _validateCode() async {
    final code = _codeController.text.trim();
    final isValidFuture = _isValidRoomCode(code);
    final isValid = await isValidFuture;
    if (isValid != _isValidCode) {
      setState(() {
        _isValidCode = isValid;
      });
      if (isValid) {
        _extractNetworkInfo(code);
      } else {
        setState(() {
          _networkName = null;
          _networkKey = null;
        });
      }
    }
  }

  // 从房间码中提取网络信息
  Future<void> _extractNetworkInfo(String code) async {
    if (!code.startsWith('U/')) return;
    final parts = code.substring(2).split('-');
    if (parts.length != 4) return;
    setState(() {
      _networkName = 'scaffolding-mc-${parts[0]}-${parts[1]}';
      _networkKey = '${parts[2]}-${parts[3]}';
    });
    LogUtil.log('网络名称: $_networkName', level: 'INFO');
    LogUtil.log('网络密钥: $_networkKey', level: 'INFO');
  }

  // 检查房间码是否有效
  Future<bool> _isValidRoomCode(String code) async {
    if (!RegExp(
      r'^U/[0-9A-HJ-NP-Z]{4}-[0-9A-HJ-NP-Z]{4}-[0-9A-HJ-NP-Z]{4}-[0-9A-HJ-NP-Z]{4}$',
    ).hasMatch(code)) {
      return false;
    }
    // 有效字符集
    const List<String> validChars = [
      '0',
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      'A',
      'B',
      'C',
      'D',
      'E',
      'F',
      'G',
      'H',
      'J',
      'K',
      'L',
      'M',
      'N',
      'P',
      'Q',
      'R',
      'S',
      'T',
      'U',
      'V',
      'W',
      'X',
      'Y',
      'Z',
    ];
    final codeContent = code.substring(2).replaceAll('-', '');
    int value = 0;
    for (int i = 0; i < codeContent.length; i++) {
      final charIndex = validChars.indexOf(codeContent[i]);
      if (charIndex == -1) return false;
      int contribution = charIndex;
      for (int j = 0; j < i; j++) {
        contribution = (contribution * 34) % 7;
      }
      value = (value + contribution) % 7;
    }
    return value == 0;
  }

  // 启动EasyTier
  Future<bool> _startEasyTier() async {
    if (_isEasyTierRunning || _easyTierProcess != null) {
      LogUtil.log('EasyTier已在运行中', level: 'INFO');
      return true;
    }
    if (_networkName == null || _networkKey == null || _machineId == null) {
      LogUtil.log('缺少启动EasyTier所需的信息', level: 'ERROR');
      return false;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('SelectedPath') ?? '';
      final path = prefs.getString('Path_$name') ?? '';
      final String core =
          ('$path${Platform.pathSeparator}easytier${Platform.pathSeparator}easytier-core');
      final args = [
        '--no-tun',
        '--dhcp',
        '--network-name',
        _networkName!,
        '--network-secret',
        _networkKey!,
        '--machine-id',
        _machineId!,
        '--listeners',
        'udp:0',
        '-p',
        widget.etServer,
      ];
      LogUtil.log(
        '正在通过 ${widget.etServer} 节点启动 EasyTier: $core ${args.join(' ')}',
        level: 'INFO',
      );
      _easyTierProcess = await Process.start(core, args);
      _easyTierProcess!.stdout.transform(utf8.decoder).listen((data) {
        if (data.contains('Connection established') ||
            data.contains('Connection success') ||
            data.contains('connected to') ||
            data.contains('relay connection') ||
            data.contains('dhcp ip changed')) {
          LogUtil.log('检测到EasyTier连接成功信息', level: 'INFO');
          _detectPeers();
        }
      });
      _easyTierProcess!.stderr.transform(utf8.decoder).listen((data) {
        LogUtil.log('EasyTier错误: $data', level: 'ERROR');
      });
      _easyTierProcess!.exitCode.then((code) {
        LogUtil.log('EasyTier进程退出,退出码: $code', level: 'INFO');
        if (mounted) {
          setState(() {
            _isEasyTierRunning = false;
            _easyTierProcess = null;
          });
        }
        MemberPage._persistIsEasyTierRunning = false;
        MemberPage._persistEasyTierProcess = null;
      });
      setState(() {
        _isEasyTierRunning = true;
      });
      MemberPage._persistIsEasyTierRunning = true;
      MemberPage._persistEasyTierProcess = _easyTierProcess;
      LogUtil.log('EasyTier启动成功', level: 'INFO');
      return true;
    } catch (e) {
      LogUtil.log('启动EasyTier失败: $e', level: 'ERROR');
      return false;
    }
  }

  // 停止EasyTier
  Future<void> _stopEasyTier() async {
    if (!_isEasyTierRunning || _easyTierProcess == null) {
      LogUtil.log('EasyTier未在运行', level: 'INFO');
      return;
    }
    try {
      LogUtil.log('正在停止EasyTier', level: 'INFO');
      _easyTierProcess!.kill(ProcessSignal.sigterm);
      await _easyTierProcess!.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _easyTierProcess!.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      if (mounted) {
        setState(() {
          _isEasyTierRunning = false;
          _easyTierProcess = null;
        });
      } else {
        _isEasyTierRunning = false;
        _easyTierProcess = null;
        MemberPage._persistIsEasyTierRunning = false;
        MemberPage._persistEasyTierProcess = null;
      }
      LogUtil.log('EasyTier已停止', level: 'INFO');
    } catch (e) {
      LogUtil.log('停止EasyTier失败: $e', level: 'ERROR');
    }
  }

  // 生成随机端口并检查可用性
  Future<int> _findAvailablePort() async {
    int attempts = 0;
    while (true) {
      attempts++;
      int port = 1024 + _random.nextInt(65535 - 1024);
      try {
        final socket = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          port,
          shared: true,
        );
        await socket.close();
        LogUtil.log('找到可用的随机端口: $port (尝试次数: $attempts)', level: 'INFO');
        return port;
      } catch (e) {
        LogUtil.log('端口 $port 被占用，尝试另一个随机端口', level: 'INFO');
      }
    }
  }

  // 检测peers并尝试连接到服务器
  Future<void> _detectPeers() async {
    if (!_isEasyTierRunning) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('SelectedPath') ?? '';
      final path = prefs.getString('Path_$name') ?? '';
      final String cliPath =
          ('$path${Platform.pathSeparator}easytier${Platform.pathSeparator}easytier-cli');
      LogUtil.log('执行easytier-cli --output json peer', level: 'INFO');
      final ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run(cliPath, [
          '--output',
          'json',
          'peer',
        ], stdoutEncoding: null);
      } else {
        result = await Process.run(cliPath, ['--output', 'json', 'peer']);
      }
      if (result.exitCode == 0) {
        String output;
        if (Platform.isWindows) {
          try {
            output = utf8.decode(result.stdout as List<int>);
            jsonDecode(output);
          } catch (e) {
            LogUtil.log('UTF-8 解码失败: $e, 尝试使用 GBK 解码', level: 'WARNING');
            try {
              output = gbk.decode(result.stdout as List<int>);
            } catch (e2) {
              LogUtil.log('GBK 解码失败: $e2', level: 'ERROR');
              return;
            }
          }
        } else {
          output = result.stdout.toString();
        }
        List<dynamic> peerList;
        peerList = jsonDecode(output);
        String? serverIP;
        int? serverPort;
        for (var peer in peerList) {
          final hostname = peer['hostname']?.toString() ?? '';
          if (hostname.startsWith('scaffolding-mc-server-')) {
            final cidr = peer['cidr']?.toString() ?? '';
            final ipv4 = peer['ipv4']?.toString() ?? '';
            if (ipv4.isNotEmpty) {
              serverIP = ipv4;
            } else if (cidr.contains('/')) {
              serverIP = cidr.split('/')[0];
            }
            final portMatch = RegExp(
              r'scaffolding-mc-server-(\d+)',
            ).firstMatch(hostname);
            if (portMatch != null && portMatch.groupCount >= 1) {
              serverPort = int.tryParse(portMatch.group(1)!);
            }
            if (serverIP != null && serverPort != null) {
              LogUtil.log(
                '在EasyTier网络中发现Scaffolding服务器: $serverIP:$serverPort (主机名: $hostname)',
                level: 'INFO',
              );
              break;
            }
          }
        }
        if (serverIP != null && serverPort != null) {
          int localPort = await _findAvailablePort();
          LogUtil.log(
            '正在转发Scaffolding端口: $serverIP:$serverPort 到 127.0.0.1:$localPort',
            level: 'INFO',
          );
          await Process.run(
            cliPath,
            'port-forward add tcp 127.0.0.1:$localPort $serverIP:$serverPort'
                .split(' '),
          );
          setState(() {
            _ipAddress = serverIP;
            MemberPage._persistIpAddress = serverIP;
          });
          _connectToFoundServer('127.0.0.1', localPort, serverIP, serverPort);
        } else {
          LogUtil.log('未能从EasyTier网络中找到Scaffolding服务器', level: 'WARN');
        }
      } else {
        LogUtil.log('easytier-cli peer命令失败: ${result.stderr}', level: 'ERROR');
      }
    } catch (e) {
      LogUtil.log('执行peers检测时出错: $e', level: 'ERROR');
    }
  }

  // 读取App版本
  Future<String> _loadAppVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final version = prefs.getString('version') ?? "1.0.0";
    return version;
  }

  // 检测核心版本
  Future<String> _checkCoreVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('SelectedPath') ?? '';
    final path = prefs.getString('Path_$name') ?? '';
    final String core =
        ('$path${Platform.pathSeparator}easytier${Platform.pathSeparator}easytier-core');
    try {
      final ProcessResult proc = await Process.run(core, ['--version']);
      final String output = proc.stdout.toString().trim();
      if (output.contains('easytier-core ')) {
        final String versionWithHash = output.split('easytier-core ')[1];
        if (versionWithHash.contains('-')) {
          return versionWithHash.split('-')[0];
        }
        return versionWithHash;
      }
      return output;
    } catch (e) {
      LogUtil.log('获取EasyTier核心版本失败: $e', level: 'ERROR');
      return "未知";
    }
  }

  // 连接到在EasyTier网络中发现的服务器
  Future<void> _connectToFoundServer(
    String localAddress,
    int localPort,
    String originalServerIP,
    int originalServerPort,
  ) async {
    try {
      LogUtil.log(
        '正在连接到Scaffolding服务器: $localAddress:$localPort (原始地址: $originalServerIP:$originalServerPort)',
        level: 'INFO',
      );
      if (mounted) {
        setState(() {
          _isConnecting = true;
        });
      }
      final appVersion = await _loadAppVersion();
      final coreVersion = await _checkCoreVersion();
      final myEasytierId = await _getMyEasyTierId();
      _client = OnlineCenterClient(
        serverAddress: localAddress,
        serverPort: localPort,
        playerName: _playerName ?? 'Guest',
        machineId: _machineId ?? const Uuid().v4(),
        easytierId: myEasytierId,
        vendor: 'FML $appVersion, EasyTier v$coreVersion',
        useIP: true,
      );
      await _client!.connect();
      _setupClientListeners();
      if (mounted) {
        setState(() {
          _isConnected = true;
          _isConnecting = false;
        });
        MemberPage._persistIsConnected = true;
        MemberPage._persistClient = _client;
        MemberPage._persistNetworkName = _networkName;
        MemberPage._persistNetworkKey = _networkKey;
        LogUtil.log('成功连接到Scaffolding服务器', level: 'INFO');
        setState(() {
          _ipAddress = originalServerIP;
          MemberPage._persistIpAddress = originalServerIP;
        });
        _retryGetMinecraftPort();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已连接到房间')));
      }
    } catch (e) {
      LogUtil.log('连接到Scaffolding服务器失败: $e', level: 'ERROR');
      _client?.disconnect();
      _client = null;
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  // 重试获取Minecraft端口
  Future<void> _retryGetMinecraftPort() async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      await Future.delayed(Duration(seconds: 2));
      if (_client == null || !_client!.isConnected) {
        LogUtil.log('第$attempt次尝试: 客户端连接已断开，停止重试', level: 'WARNING');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('与服务器的连接已断开'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      try {
        await _client!.getMinecraftServerPort();
        LogUtil.log('第$attempt次尝试: 已发送获取Minecraft端口请求', level: 'INFO');
      } catch (e) {
        LogUtil.log('第$attempt次尝试: 发送端口请求失败 - $e', level: 'ERROR');
        if (attempt == 3) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('无法与服务器通信，请检查网络连接'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
        continue;
      }
      await Future.delayed(Duration(seconds: 1));
      if (_minecraftServerPort != null) {
        LogUtil.log(
          '第$attempt次尝试: 已获取到Minecraft端口 $_minecraftServerPort,开始设置转发',
          level: 'INFO',
        );
        await _setupMinecraftPortForwarding();
        return;
      }
      LogUtil.log('第$attempt次尝试: 未收到Minecraft端口信息', level: 'WARNING');
      if (attempt == 3) {
        LogUtil.log(
          '已重试3次仍未收到Minecraft端口信息,可能服务器未启动Minecraft服务',
          level: 'WARNING',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('房主可能还未启动Minecraft服务器'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  // 连接到房间
  Future<void> _connectToRoom() async {
    if (!_isValidCode || _networkName == null || _networkKey == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效的房间码')));
      return;
    }
    setState(() {
      _isConnecting = true;
    });
    final easyTierStarted = await _startEasyTier();
    if (!easyTierStarted) {
      setState(() {
        _isConnecting = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('启动EasyTier失败')));
      return;
    }
    _detectPeers();
    int attempts = 0;
    Timer.periodic(const Duration(seconds: 10), (timer) {
      attempts++;
      if (!mounted || _isConnected) {
        timer.cancel();
        return;
      }
      if (attempts < 9) {
        LogUtil.log('第$attempts次尝试检测peers...', level: 'INFO');
        _detectPeers();
      } else {
        timer.cancel();
        if (mounted && !_isConnected) {
          setState(() {
            _isConnecting = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('连接超时，请检查房间码是否正确，或者房主是否已创建房间'),
              duration: Duration(seconds: 8),
            ),
          );
          _stopEasyTier();
        }
      }
    });
    Future.delayed(const Duration(seconds: 20), () {
      if (mounted && _isConnecting && !_isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('连接需要较长时间，正在建立网络连接...'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    });
  }

  // 断开连接
  Future<void> _disconnect() async {
    _minecraftLaunchTimer?.cancel();
    await _stopFakeServer();
    if (_client != null) {
      try {
        await _client?.disconnect();
      } catch (e) {
        LogUtil.log('关闭客户端连接时出错: $e', level: 'ERROR');
      }
      _client = null;
    }
    await _stopEasyTier();
    if (mounted) {
      setState(() {
        _isConnected = false;
        _players = [];
        _minecraftServerPort = null;
        _ipAddress = null;
        _peers = [];
      });
    }
    MemberPage._persistIsConnected = false;
    MemberPage._persistIsEasyTierRunning = false;
    MemberPage._persistEasyTierProcess = null;
    MemberPage._persistNetworkName = null;
    MemberPage._persistNetworkKey = null;
    MemberPage._persistClient = null;
    MemberPage._persistPlayers = [];
    MemberPage._persistMinecraftServerPort = null;
    MemberPage._persistIpAddress = null;
    MemberPage._persistFakeServer = null;
    MemberPage._persistPeers = [];
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已断开连接')));
    }
  }

  @override
  // 构建UI
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(title: const Text('加入房间')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _isConnected ? _buildConnectedView() : _buildConnectForm(),
        ),
        floatingActionButton: _isConnected
            ? FloatingActionButton(
                onPressed: _disconnect,
                tooltip: '断开连接',
                child: const Icon(Icons.logout),
              )
            : FloatingActionButton(
                onPressed: _isConnecting ? null : _connectToRoom,
                tooltip: '连接到房间',
                child: _isConnecting
                    ? const CircularProgressIndicator()
                    : const Icon(Icons.login),
              ),
      ),
    );
  }

  // 房间信息输入
  Widget _buildConnectForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('输入房间邀请码', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: '房间码 (格式: U/XXXX-XXXX-XXXX-XXXX)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.code),
                  ),
                  maxLength: 21,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Z/-]')),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('网络名称: $_networkName'),
                Text('网络密钥: $_networkKey'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 已连接
  Widget _buildConnectedView() {
    return ListView(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('连接到房间', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.check_circle),
                    const SizedBox(width: 8),
                    Text('已连接', style: TextStyle(color: Colors.green)),
                  ],
                ),
              ],
            ),
          ),
        ),
        Card(
          child: ListTile(
            title: Text('Minecraft服务器备用地址'),
            subtitle: Text('127.0.0.1:$mcPort'),
            leading: const Icon(Icons.dns),
            trailing: const Icon(Icons.copy),
            onTap: () {
              Clipboard.setData(ClipboardData(text: '127.0.0.1:$mcPort'));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
            },
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '玩家节点列表:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_peers.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 16,
                      horizontalMargin: 8,
                      columns: const [
                        DataColumn(label: Text('类型')),
                        DataColumn(label: Text('玩家')),
                        DataColumn(label: Text('客户端')),
                        DataColumn(label: Text('IP')),
                        DataColumn(label: Text('连接')),
                        DataColumn(label: Text('延迟')),
                        DataColumn(label: Text('丢包')),
                        DataColumn(label: Text('接收(rx)')),
                        DataColumn(label: Text('发送(tx)')),
                        DataColumn(label: Text('NAT类型')),
                      ],
                      rows: _peers.map((peer) {
                        String kindText = '-';
                        if (peer.playerKind == 'HOST') {
                          kindText = '房主';
                        } else if (peer.playerKind == 'GUEST') {
                          kindText = '房客';
                        }
                        return DataRow(
                          cells: [
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(width: 4),
                                  Text(kindText),
                                ],
                              ),
                            ),
                            DataCell(Text(peer.playerName ?? '-')),
                            DataCell(Text(peer.playerVendor ?? '-')),
                            DataCell(Text(peer.ipv4 ?? '-')),
                            DataCell(Text(peer.cost)),
                            DataCell(Text(peer.latency)),
                            DataCell(Text(peer.loss)),
                            DataCell(Text(peer.rx)),
                            DataCell(Text(peer.tx)),
                            DataCell(Text(peer.nat)),
                          ],
                        );
                      }).toList(),
                    ),
                  )
                else
                  const Text(
                    '暂无对等节点连接',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                if (_isEasyTierRunning && _peers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text(
                      '正在获取节点数据...',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '公共服务器列表:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (_isEasyTierRunning)
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        iconSize: 20,
                        onPressed: _refreshPeerList,
                        tooltip: '刷新节点列表',
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_servers.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 16,
                      horizontalMargin: 8,
                      columns: const [
                        DataColumn(label: Text('服务器名称')),
                        DataColumn(label: Text('连接')),
                        DataColumn(label: Text('延迟')),
                        DataColumn(label: Text('丢包')),
                        DataColumn(label: Text('接收(rx)')),
                        DataColumn(label: Text('发送(tx)')),
                        DataColumn(label: Text('隧道协议')),
                        DataColumn(label: Text('NAT类型')),
                      ],
                      rows: _servers.map((server) {
                        return DataRow(
                          cells: [
                            DataCell(Text(server.hostname)),
                            DataCell(Text(server.cost)),
                            DataCell(Text('${server.latency} ms')),
                            DataCell(Text(server.loss)),
                            DataCell(Text(server.rx)),
                            DataCell(Text(server.tx)),
                            DataCell(Text(server.tunnel)),
                            DataCell(Text(server.nat)),
                          ],
                        );
                      }).toList(),
                    ),
                  )
                else
                  const Text(
                    '暂无公共服务器连接',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                if (_isEasyTierRunning && _servers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text(
                      '正在获取服务器数据...',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(height: 64.0),
      ],
    );
  }

  // 解析EasyTier节点数据
  Map<String, List<EasyTierPeer>> parseEasyTierPeers(List<dynamic> peerList) {
    List<EasyTierPeer> peers = [];
    List<EasyTierPeer> servers = [];
    Set<String> boundPlayerIds = {};
    try {
      for (var peer in peerList) {
        if (peer['hostname']?.toString().startsWith('PublicServer') ?? false) {
          final serverData = EasyTierPeer(
            ipv4: peer['ipv4']?.toString().isEmpty ?? true
                ? null
                : peer['ipv4'].toString(),
            hostname: peer['hostname']?.toString() ?? '-',
            cost: peer['cost']?.toString() ?? '-',
            latency: peer['lat_ms']?.toString() ?? '-',
            loss: peer['loss_rate']?.toString() ?? '-',
            rx: peer['rx_bytes']?.toString() ?? '-',
            tx: peer['tx_bytes']?.toString() ?? '-',
            tunnel: peer['tunnel_proto']?.toString() ?? '-',
            nat: peer['nat_type']?.toString() ?? '-',
            version: peer['version']?.toString() ?? '-',
            id: peer['id']?.toString() ?? '',
            playerName: null,
            playerVendor: null,
            playerKind: null,
          );
          servers.add(serverData);
          continue;
        }
        final nodeId = peer['id']?.toString() ?? '';
        String? playerName;
        String? playerVendor;
        String? playerKind;
        if (_players.isNotEmpty && nodeId.isNotEmpty) {
          final matchedPlayer = _players.firstWhere(
            (player) => player.easytierId == nodeId,
            orElse: () => PlayerProfile(
              name: '',
              machineId: '',
              easytierId: '',
              vendor: '',
              kind: '',
            ),
          );
          if (matchedPlayer.name.isNotEmpty) {
            playerName = matchedPlayer.name;
            playerVendor = matchedPlayer.vendor;
            playerKind = matchedPlayer.kind;
            boundPlayerIds.add(matchedPlayer.easytierId);
            final peerData = EasyTierPeer(
              ipv4: peer['ipv4']?.toString().isEmpty ?? true
                  ? null
                  : peer['ipv4'].toString(),
              hostname: peer['hostname']?.toString() ?? '-',
              cost: peer['cost']?.toString() ?? '-',
              latency: peer['lat_ms']?.toString() ?? '-',
              loss: peer['loss_rate']?.toString() ?? '-',
              rx: peer['rx_bytes']?.toString() ?? '-',
              tx: peer['tx_bytes']?.toString() ?? '-',
              tunnel: peer['tunnel_proto']?.toString() ?? '-',
              nat: peer['nat_type']?.toString() ?? '-',
              version: peer['version']?.toString() ?? '-',
              id: nodeId,
              playerName: playerName,
              playerVendor: playerVendor,
              playerKind: playerKind,
            );
            peers.add(peerData);
          }
        }
      }
      for (var player in _players) {
        if (player.easytierId.isEmpty ||
            !boundPlayerIds.contains(player.easytierId)) {
          final unboundPlayerData = EasyTierPeer(
            ipv4: null,
            hostname: '-',
            cost: '-',
            latency: '-',
            loss: '-',
            rx: '-',
            tx: '-',
            tunnel: '-',
            nat: '-',
            version: '-',
            id: player.easytierId,
            playerName: player.name,
            playerVendor: player.vendor,
            playerKind: player.kind,
          );
          peers.add(unboundPlayerData);
        }
      }
    } catch (e) {
      LogUtil.log('解析对等节点数据失败: $e', level: 'ERROR');
    }
    return {'peers': peers, 'servers': servers};
  }

  // 刷新EasyTier节点列表
  Future<void> _refreshPeerList() async {
    if (!_isEasyTierRunning) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('SelectedPath') ?? '';
      final path = prefs.getString('Path_$name') ?? '';
      final String cli =
          ('$path${Platform.pathSeparator}easytier${Platform.pathSeparator}easytier-cli');
      final ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run(cli, [
          '--output',
          'json',
          'peer',
        ], stdoutEncoding: null);
      } else {
        result = await Process.run(cli, ['--output', 'json', 'peer']);
      }
      if (result.exitCode == 0) {
        String output;
        if (Platform.isWindows) {
          try {
            output = utf8.decode(result.stdout as List<int>);
            jsonDecode(output);
          } catch (e) {
            LogUtil.log('UTF-8 解码失败: $e, 尝试使用 GBK 解码', level: 'WARNING');
            try {
              output = gbk.decode(result.stdout as List<int>);
            } catch (e2) {
              LogUtil.log('GBK 解码失败: $e2', level: 'ERROR');
              return;
            }
          }
        } else {
          output = result.stdout.toString();
        }
        List<dynamic> peerList;
        peerList = jsonDecode(output);
        final parsedData = parseEasyTierPeers(peerList);
        if (mounted) {
          setState(() {
            _peers = parsedData['peers'] ?? [];
            _servers = parsedData['servers'] ?? [];
          });
          MemberPage._persistPeers = _peers;
        }
        LogUtil.log(
          '刷新对等节点列表成功，共${_peers.length}个玩家节点，${_servers.length}个服务器节点',
          level: 'INFO',
        );
      } else {
        LogUtil.log(
          '执行easytier-cli peer命令失败,退出码:${result.exitCode}',
          level: 'ERROR',
        );
        LogUtil.log('错误输出：${result.stderr}', level: 'ERROR');
      }
    } catch (e) {
      LogUtil.log('刷新EasyTier对等节点列表失败: $e', level: 'ERROR');
    }
  }

  // 获取本机的EasyTier ID
  Future<String> _getMyEasyTierId() async {
    if (!_isEasyTierRunning) return '';
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('SelectedPath') ?? '';
      final path = prefs.getString('Path_$name') ?? '';
      final String cli =
          ('$path${Platform.pathSeparator}easytier${Platform.pathSeparator}easytier-cli');
      ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run(cli, [
          '--output',
          'json',
          'peer',
        ], stdoutEncoding: null);
      } else {
        result = await Process.run(cli, ['--output', 'json', 'peer']);
      }
      if (result.exitCode == 0) {
        String output;
        if (Platform.isWindows) {
          try {
            output = utf8.decode(result.stdout as List<int>);
            jsonDecode(output);
          } catch (e) {
            LogUtil.log('UTF-8 解码失败: $e, 尝试使用 GBK 解码', level: 'WARNING');
            output = gbk.decode(result.stdout as List<int>);
          }
        } else {
          output = result.stdout.toString();
        }
        final List<dynamic> peerList = jsonDecode(output);
        for (var peer in peerList) {
          if (peer['cost']?.toString() == 'Local') {
            final peerId = peer['id']?.toString() ?? '';
            if (peerId.isNotEmpty) {
              LogUtil.log('本机EasyTier ID: $peerId', level: 'INFO');
              return peerId;
            }
          }
        }
      }
      LogUtil.log('无法从peer列表获取EasyTier ID', level: 'ERROR');
      return '';
    } catch (e) {
      LogUtil.log('获取EasyTier ID时出错: $e', level: 'ERROR');
      return '';
    }
  }
}
