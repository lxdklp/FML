import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_gbk2utf8/flutter_gbk2utf8.dart';
import 'package:fml/function/log.dart';
import 'package:fml/function/online/scaffolding/server.dart';
import 'package:fml/function/online/scanner.dart';

// EasyTier对等节点类
class PlayerList {
  final String? ipv4;
  final String name;
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

  PlayerList({
    this.ipv4,
    required this.name,
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

class OwnerPage extends StatefulWidget {
  final int port;
  final String etServer;
  const OwnerPage({super.key, required this.port, required this.etServer});

  // 静态变量用于在页面重建之间保持状态
  static String? _persistRoomCode;
  static String? _persistNetworkName;
  static String? _persistNetworkKey;
  static OnlineCenterServer? _persistTcpServer;
  static int _persistTcpServerPort = 25565;
  static int _persistPort = -1;
  static bool persistIsServerRunning = false;
  static Process? _easyTierProcess;
  static String? _machineId;
  static String? _easytierId;

  @override
  OwnerPageState createState() => OwnerPageState();
}

class OwnerPageState extends State<OwnerPage> {
  int _port = -1;
  String? _roomCode;
  String? _networkName;
  String? _networkKey;
  OnlineCenterServer? _tcpServer;
  int _tcpServerPort = 25565;
  bool _isServerRunning = false;
  String _playerName = "房主";
  final Random _random = Random();
  Process? _easyTierProcess;
  String? _machineId;
  String? _easytierId;
  bool _isEasyTierRunning = false;
  List<PlayerList> _peers = [];
  List<PlayerList> _servers = [];
  Timer? _peerListRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadPlayerName();
    _initMachineId();
    _roomCode = OwnerPage._persistRoomCode;
    _networkName = OwnerPage._persistNetworkName;
    _networkKey = OwnerPage._persistNetworkKey;
    _tcpServer = OwnerPage._persistTcpServer;
    _tcpServerPort = OwnerPage._persistTcpServerPort;
    _port = OwnerPage._persistPort;
    _isServerRunning = OwnerPage.persistIsServerRunning;
    _easyTierProcess = OwnerPage._easyTierProcess;
    _machineId = OwnerPage._machineId;
    _easytierId = OwnerPage._easytierId;
    _isEasyTierRunning = _easyTierProcess != null;
    _peerListRefreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isEasyTierRunning && mounted) {
        _refreshPeerList();
      }
    });
    _startTcpServer();
    if (_roomCode == null) {
      _generateRoomCode();
    }
  }

  // 初始化机器ID
  Future<void> _initMachineId() async {
    if (_machineId != null) return;
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
      OwnerPage._machineId = machineId;
    } catch (e) {
      final tempId = const Uuid().v4();
      setState(() {
        _machineId = tempId;
      });
      OwnerPage._machineId = tempId;
      LogUtil.log('生成临时机器ID: $_machineId', level: 'INFO');
    }
  }

  // 获取 easytier ID
  Future<void> _getEasytierId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('SelectedPath') ?? '';
      final path = prefs.getString('Path_$name') ?? '';
      final String cli = ('$path${Platform.pathSeparator}easytier${Platform.pathSeparator}easytier-cli');
      final proc = await Process.run(
        cli,
        ['--output', 'json', 'peer'],
        stdoutEncoding: Platform.isWindows ? null : utf8,
      );
      String output;
      if (Platform.isWindows) {
        try {
          output = utf8.decode(proc.stdout);
          jsonDecode(output);
        } catch (e) {
          LogUtil.log('UTF-8解码失败,尝试GBK解码: $e', level: 'WARNING');
          output = gbk.decode(proc.stdout);
        }
      } else {
        output = proc.stdout.toString();
      }
      final List<dynamic> peer = jsonDecode(output);
      bool found = false;
      for (var item in peer) {
        if (item['cost'] == 'Local') {
          String id = item['id'];
          LogUtil.log('easytier ID: $id ', level: 'INFO');
          setState(() {
            _easytierId = id;
          });
          found = true;
          break;
        }
      }
      if (!found) {
        LogUtil.log('错误: 无法找到本机的EasyTier节点', level: 'ERROR');
      }
    } catch (e) {
      LogUtil.log('获取 easytier ID 失败: $e', level: 'ERROR');
    }
  }

  // 端口发现
  Future<void> _scanningPort() async {
    LogUtil.log('开始扫描', level: 'INFO');
    final port = await getPort();
    if (port != null) {
      setState(() {
        _port = port;
      });
      LogUtil.log('发现的端口: $port', level: 'INFO');
    } else {
      LogUtil.log('端口扫描超时，未发现新的端口', level: 'WARNING');
    }
  }

  @override
  void dispose() {
    _peerListRefreshTimer?.cancel();
    super.dispose();
  }

  // 有效字符集
  static const List<String> _validChars = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K',
    'L', 'M', 'N', 'P', 'Q', 'R', 'S', 'T', 'U', 'V',
    'W', 'X', 'Y', 'Z'
  ];

  // 生成房间码
  Future<void> _generateRoomCode() async {
    final random = Random.secure();
    final List<int> charIndices = List.generate(15, (_) => random.nextInt(34));
    int partialValue = 0;
    for (int i = 0; i < 15; i++) {
      int contribution = charIndices[i];
      for (int j = 0; j < i; j++) {
        contribution = (contribution * 34) % 7;
      }
      partialValue = (partialValue + contribution) % 7;
    }
    int remainder = partialValue % 7;
    int needed = (7 - remainder) % 7;
    int weight = 1;
    for (int i = 0; i < 15; i++) {
      weight = (weight * 34) % 7;
    }
    int lastCharIndex = 0;
    for (int i = 0; i < 34; i++) {
      if ((i * weight) % 7 == needed) {
        lastCharIndex = i;
        break;
      }
    }
    final List<String> chars = charIndices.map((i) => _validChars[i]).toList();
    chars.add(_validChars[lastCharIndex]);
    final code = 'U/${chars.sublist(0, 4).join()}-${chars.sublist(4, 8).join()}-${chars.sublist(8, 12).join()}-${chars.sublist(12, 16).join()}';
    final parts = code.substring(2).split('-');
    setState(() {
      _roomCode = code;
      _networkName = 'scaffolding-mc-${parts[0]}-${parts[1]}';
      _networkKey = '${parts[2]}-${parts[3]}';
    });
    OwnerPage._persistRoomCode = _roomCode;
    OwnerPage._persistNetworkName = _networkName;
    OwnerPage._persistNetworkKey = _networkKey;
    if (kDebugMode && !(await _isValidCode(code))) {
      LogUtil.log('生成的代码验证失败: $code', level: 'ERROR');
    } else {
      LogUtil.log('生成房间码: $_roomCode', level: 'INFO');
      LogUtil.log('网络名称: $_networkName', level: 'INFO');
      LogUtil.log('网络密钥: $_networkKey', level: 'INFO');
      if (_port > 0 && !_isServerRunning) {
        Future.delayed(const Duration(milliseconds: 100), () {
          _startTcpServer();
        });
      }
    }
  }

  // 验证房间码
  Future<bool> _isValidCode(String code) async {
    if (!RegExp(r'^U/[0-9A-HJ-NP-Z]{4}-[0-9A-HJ-NP-Z]{4}-[0-9A-HJ-NP-Z]{4}-[0-9A-HJ-NP-Z]{4}$')
        .hasMatch(code)) {
      return false;
    }
    final codeContent = code.substring(2).replaceAll('-', '');
    int value = 0;
    for (int i = 0; i < codeContent.length; i++) {
      final charIndex = _validChars.indexOf(codeContent[i]);
      if (charIndex == -1) return false;
      int contribution = charIndex;
      for (int j = 0; j < i; j++) {
        contribution = (contribution * 34) % 7;
      }
      value = (value + contribution) % 7;
    }
    return value == 0;
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
    final String core = ('$path${Platform.pathSeparator}easytier${Platform.pathSeparator}easytier-core');
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

  // 生成随机端口并检查可用性
  Future<int> _findAvailablePort() async {
    int maxAttempts = 20;
    int attempts = 0;
    while (attempts < maxAttempts) {
      attempts++;
      int port = 1024 + _random.nextInt(65535 - 1024);
      try {
        final socket = await ServerSocket.bind(InternetAddress.anyIPv4, port, shared: true);
        await socket.close();
        LogUtil.log('找到可用的随机端口: $port (尝试次数: $attempts)', level: 'INFO');
        return port;
      } catch (e) {
        LogUtil.log('端口 $port 被占用，尝试另一个随机端口', level: 'INFO');
      }
    }
    throw Exception('尝试$maxAttempts次后仍无法找到可用端口');
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
    int maxRetries = 5;
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final name = prefs.getString('SelectedPath') ?? '';
        final path = prefs.getString('Path_$name') ?? '';
        final String core = ('$path${Platform.pathSeparator}easytier${Platform.pathSeparator}easytier-core');
        int scaffoldingPort = _tcpServerPort;
        int minecraftPort = _port;
        if (attempt > 0) {
          scaffoldingPort = await _findAvailablePort();
          if (_tcpServer != null) {
            await _tcpServer!.stop();
            _tcpServer = OnlineCenterServer(
              hostName: _playerName,
              hostVendor: _tcpServer!.hostVendor,
              port: scaffoldingPort,
              minecraftServerPort: minecraftPort
            );
            OwnerPage._persistTcpServer = _tcpServer;
            OwnerPage._persistTcpServerPort = scaffoldingPort;
            OwnerPage._persistPort = minecraftPort;
            setState(() {
              _tcpServerPort = scaffoldingPort;
              _port = minecraftPort;
            });
            LogUtil.log('TCP服务器端口更新为: $scaffoldingPort', level: 'INFO');
          }
        }
        final hostname = 'scaffolding-mc-server-$scaffoldingPort';
        LogUtil.log('设置EasyTier主机名: $hostname', level: 'INFO');
        final args = [
          '--no-tun',
          '--network-name', _networkName!,
          '--network-secret', _networkKey!,
          '--machine-id', _machineId!,
          '--hostname', hostname,
          '--listeners', 'udp:0',
          '--ipv4', '10.144.144.1',
          '-p', widget.etServer,
        ];
        LogUtil.log('正在通过 ${widget.etServer} 节点启动 EasyTier ${attempt > 0 ? " (尝试 ${attempt+1}/$maxRetries)" : ""}: $core ${args.join(' ')}', level: 'INFO');
        _easyTierProcess = await Process.start(core, args);
        OwnerPage._easyTierProcess = _easyTierProcess;
        _easyTierProcess!.stdout.transform(utf8.decoder).listen((data) {
          LogUtil.log('EasyTier输出: $data', level: 'INFO');
        });
        bool hasPortConflict = false;
        _easyTierProcess!.stderr.transform(utf8.decoder).listen((data) {
          LogUtil.log('EasyTier错误: $data', level: 'ERROR');
          if (data.contains('Address already in use') || data.contains('error code 48')) {
            hasPortConflict = true;
          }
        });
        await Future.delayed(const Duration(seconds: 1));
        try {
          int? exitCode;
          try {
            exitCode = await _easyTierProcess!.exitCode.timeout(
              const Duration(milliseconds: 100),
            );
          } on TimeoutException {
            exitCode = null;
          }
          if (exitCode != null) {
            if (hasPortConflict && attempt < maxRetries - 1) {
              LogUtil.log('检测到端口冲突,将尝试使用不同的端口 (尝试 ${attempt+1}/$maxRetries)', level: 'WARNING');
            } else if (exitCode != 0) {
              LogUtil.log('EasyTier启动失败,退出码: $exitCode', level: 'ERROR');
              return false;
            }
          }
        } catch (e) {
          LogUtil.log('检查EasyTier启动状态时出错: $e', level: 'ERROR');
        }
        _easyTierProcess!.exitCode.then((code) {
          LogUtil.log('EasyTier进程退出,退出码: $code', level: 'INFO');
          if (mounted) {
            setState(() {
              _isEasyTierRunning = false;
              _easyTierProcess = null;
            });
            OwnerPage._easyTierProcess = null;
          }
        });
        setState(() {
          _isEasyTierRunning = true;
        });
        LogUtil.log('EasyTier启动成功', level: 'INFO');
        _startPortForwarding();
        return true;
      } catch (e) {
        LogUtil.log('启动EasyTier失败 (尝试 ${attempt+1}/$maxRetries): $e', level: 'ERROR');
        if (attempt < maxRetries - 1) {
          LogUtil.log('将使用不同端口重试...', level: 'INFO');
          if (_easyTierProcess != null) {
            try {
              _easyTierProcess!.kill();
            } catch (killError) {
              LogUtil.log('终止EasyTier进程时出错: $killError', level: 'ERROR');
            }
            _easyTierProcess = null;
          }
          await Future.delayed(Duration(seconds: 1));
        }
      }
    }
    LogUtil.log('在尝试所有可能的端口后,EasyTier启动失败', level: 'ERROR');
    return false;
  }

  // 端口转发
  Future<void> _startPortForwarding() async {
    if (!_isEasyTierRunning || _easyTierProcess == null) {
      LogUtil.log('EasyTier未在运行,无法进行端口转发', level: 'WARNING');
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('SelectedPath') ?? '';
      final path = prefs.getString('Path_$name') ?? '';
      final String cli = ('$path${Platform.pathSeparator}easytier${Platform.pathSeparator}easytier-cli');
      LogUtil.log('正在请求EasyTier进行端口转发', level: 'INFO');
      LogUtil.log('转发tcp服务器: 0.0.0.0:$_tcpServerPort 10.144.144.1:$_tcpServerPort', level: 'INFO');
      await Process.start(cli, 'port-forward add tcp 0.0.0.0:$_tcpServerPort 10.144.144.1:$_tcpServerPort'.split(' '));
      LogUtil.log('转发游戏服务器: 0.0.0.0:$_port 10.144.144.1:$_port', level: 'INFO');
      await Process.start(cli, 'port-forward add tcp 0.0.0.0:$_port 10.144.144.1:$_port'.split(' '));
      LogUtil.log('端口转发请求已发送', level: 'INFO');
    } catch (e) {
      LogUtil.log('请求端口转发失败: $e', level: 'ERROR');
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
          // 超时强制结束
          _easyTierProcess!.kill(ProcessSignal.sigkill);
          return -1;
        }
      );
      setState(() {
        _isEasyTierRunning = false;
        _easyTierProcess = null;
        _port = -1;
      });
      OwnerPage._easyTierProcess = null;
      OwnerPage._persistPort = -1;
      LogUtil.log('EasyTier已停止', level: 'INFO');
    } catch (e) {
      LogUtil.log('停止EasyTier失败: $e', level: 'ERROR');
    }
  }

  // 启动TCP服务器
  Future<void> _startTcpServer() async {
    if (_isServerRunning) {
      LogUtil.log('TCP服务器已经在运行', level: 'INFO');
      return;
    }
    await _scanningPort();
    if (_port <= 0) {
      LogUtil.log('Minecraft服务器尚未启动,无法启动TCP服务器', level: 'WARNING');
      return;
    }
    try {
      final appVersion = await _loadAppVersion();
      final coreVersion = await _checkCoreVersion();
      _tcpServerPort = await _findAvailablePort();
      _tcpServer = OnlineCenterServer(
        hostName: _playerName,
        hostVendor: 'FML $appVersion, EasyTier v$coreVersion',
        port: _tcpServerPort,
        minecraftServerPort: _port
      );
      await _tcpServer!.start();
      // 启动EasyTier网络
      final easyTierStarted = await _startEasyTier();
      await _getEasytierId();
      await _tcpServer!.addHostPlayer(_machineId ?? 'unknown-machine-id', _easytierId ?? '');
      setState(() {
        _isServerRunning = true;
      });
      OwnerPage._persistTcpServer = _tcpServer;
      OwnerPage._persistTcpServerPort = _tcpServerPort;
      OwnerPage._persistPort = _port;
      OwnerPage.persistIsServerRunning = _isServerRunning;
      LogUtil.log('TCP服务器启动成功,端口: $_tcpServerPort', level: 'INFO');
      String message = '联机服务器启动成功,端口: $_tcpServerPort';
      if (!easyTierStarted) {
        message += ' (EasyTier启动失败)';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message))
      );
    } catch (e) {
      LogUtil.log('启动TCP服务器失败: $e', level: 'ERROR');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('启动联机服务器失败: $e'))
      );
      await _stopEasyTier();
    }
  }

  // 停止TCP服务器
  Future<void> _stopTcpServer() async {
    if (!_isServerRunning) return;
    try {
      await _stopEasyTier();
      await _tcpServer?.stop();
      _tcpServer = null;
      setState(() {
        _isServerRunning = false;
      });
      OwnerPage._persistTcpServer = null;
      OwnerPage.persistIsServerRunning = false;
      LogUtil.log('TCP服务器已停止', level: 'INFO');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('联机服务器已停止'))
      );
      Navigator.pop(context);
    } catch (e) {
      LogUtil.log('停止TCP服务器失败: $e', level: 'ERROR');
    }
  }

  // 解析EasyTier对等节点数据
  Map<String, List<PlayerList>> parsePlayerLists(List<dynamic> peerList) {
    List<PlayerList> peers = [];
    List<PlayerList> servers = [];
    Set<String> boundPlayerIds = {};
    try {
      for (var peer in peerList) {
        if (peer['hostname']?.toString().startsWith('PublicServer') ?? false) {
          final serverData = PlayerList(
            ipv4: peer['ipv4']?.toString().isEmpty ?? true ? null : peer['ipv4'].toString(),
            name: peer['hostname']?.toString() ?? '-',
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
        if (_tcpServer != null && nodeId.isNotEmpty) {
          final matchedPlayer = _tcpServer!.players.firstWhere(
            (player) => player.easytierId == nodeId,
            orElse: () => PlayerProfile(
              name: '',
              machineId: '',
              easytierId: '',
              vendor: '',
              kind: '',
              socketId: '',
            ),
          );
          if (matchedPlayer.name.isNotEmpty) {
            playerName = matchedPlayer.name;
            playerVendor = matchedPlayer.vendor;
            playerKind = matchedPlayer.kind;
            boundPlayerIds.add(matchedPlayer.easytierId);
            final playerData = PlayerList(
              ipv4: peer['ipv4']?.toString().isEmpty ?? true ? null : peer['ipv4'].toString(),
              name: peer['hostname']?.toString() ?? '-',
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
            peers.add(playerData);
          }
        }
      }
      if (_tcpServer != null) {
        for (var player in _tcpServer!.players) {
          if (player.easytierId.isEmpty || !boundPlayerIds.contains(player.easytierId)) {
            final unboundPlayerData = PlayerList(
              ipv4: null,
              name: '-',
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
      }
    } catch (e) {
      LogUtil.log('解析对等节点数据失败: $e', level: 'ERROR');
    }
    return {'peers': peers, 'servers': servers};
  }

  // 刷新EasyTier对等节点列表
  Future<void> _refreshPeerList() async {
    if (!_isEasyTierRunning) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('SelectedPath') ?? '';
      final path = prefs.getString('Path_$name') ?? '';
      final String cli = ('$path${Platform.pathSeparator}easytier${Platform.pathSeparator}easytier-cli');
      final result = await Process.run(
        cli,
        ['--output', 'json', 'peer'],
        stdoutEncoding: Platform.isWindows ? null : utf8,
      );
      if (result.exitCode == 0) {
        String output;
        if (Platform.isWindows) {
          try {
            output = utf8.decode(result.stdout);
            jsonDecode(output);
          } catch (e) {
            LogUtil.log('UTF-8解码失败,尝试GBK解码: $e', level: 'WARNING');
            output = gbk.decode(result.stdout);
          }
        } else {
          output = result.stdout.toString();
        }
        final List<dynamic> peerList = jsonDecode(output);
        final parsedData = parsePlayerLists(peerList);
        if (mounted) {
          setState(() {
            _peers = parsedData['peers'] ?? [];
            _servers = parsedData['servers'] ?? [];
          });
        }
      } else {
        LogUtil.log('执行easytier-cli peer命令失败,退出码:${result.exitCode}', level: 'ERROR');
        LogUtil.log('错误输出：${result.stderr}', level: 'ERROR');
      }
    } catch (e) {
      LogUtil.log('刷新EasyTier对等节点列表失败: $e', level: 'ERROR');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建房间'),
      ),
      body: Center(
        child: (_port < 0 && !_isServerRunning)
            ? const Text('正在等待局域网游戏启动...\n请在单人游戏中打开局域网开放')
            : ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_roomCode != null) ...[
                            Text(
                              '邀请码:',
                              style: Theme.of(context).textTheme.titleLarge
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(_roomCode!,
                                    style: Theme.of(context).textTheme.headlineMedium
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: _roomCode!));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('房间码已复制到剪贴板'))
                                    );
                                  },
                                ),
                              ],
                            ),
                            const Divider(),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'Scaffolding 协议服务器: ',
                                            style: TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                          Text(
                                            _isServerRunning ? "运行中" : "正在启动",
                                            style: TextStyle(
                                              color: _isServerRunning ? Colors.green : Colors.orange,
                                              fontWeight: FontWeight.bold
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Text(
                                            'EasyTier 网络: ',
                                            style: TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                          Text(
                                            _isEasyTierRunning ? "已连接" : "正在连接",
                                            style: TextStyle(
                                              color: _isEasyTierRunning ? Colors.green : Colors.orange,
                                              fontWeight: FontWeight.bold
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      if (_isServerRunning)
                                        Text('Scaffolding 协议端口: $_tcpServerPort'),
                                        Text('Minecraft 服务器端口: $_port')
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
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
                            const Text('EasyTier网络信息:'),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('网络名称: $_networkName'),
                                      const SizedBox(height: 4),
                                      Text('网络密钥: $_networkKey'),
                                    ],
                                  ),
                                ),
                              ],
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
                              const Text('玩家列表:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                  DataColumn(label: Text('接收')),
                                  DataColumn(label: Text('发送')),
                                  DataColumn(label: Text('NAT类型')),
                                ],
                                rows: _peers.map((peer) {
                                  String kindText = '-';
                                  if (peer.playerKind == 'HOST') {
                                    kindText = '房主';
                                  } else if (peer.playerKind == 'GUEST') {
                                    kindText = '房客';
                                  }
                                  return DataRow(cells: [
                                    DataCell(Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const SizedBox(width: 4),
                                        Text(kindText),
                                      ],
                                    )),
                                    DataCell(Text(peer.playerName ?? '-')),
                                    DataCell(Text(peer.playerVendor ?? '-')),
                                    DataCell(Text(peer.ipv4 ?? '-')),
                                    DataCell(Text(peer.cost)),
                                    DataCell(Text(peer.latency)),
                                    DataCell(Text(peer.loss)),
                                    DataCell(Text(peer.rx)),
                                    DataCell(Text(peer.tx)),
                                    DataCell(Text(peer.nat)),
                                  ]);
                                }).toList(),
                              ),
                            )
                          else
                            const Text('暂无对等节点连接', style: TextStyle(fontStyle: FontStyle.italic)),
                          if (_isEasyTierRunning && _peers.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 8.0),
                              child: Text('正在获取节点数据...', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
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
                              const Text('当前使用的公共服务器,感谢各位服务器维护者:',
                                style: TextStyle(fontWeight: FontWeight.bold)
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
                                  DataColumn(label: Text('接收')),
                                  DataColumn(label: Text('发送')),
                                  DataColumn(label: Text('隧道协议')),
                                  DataColumn(label: Text('NAT类型')),
                                ],
                                rows: _servers.map((server) {
                                  return DataRow(cells: [
                                    DataCell(Text(server.name)),
                                    DataCell(Text(server.cost)),
                                    DataCell(Text('${server.latency} ms')),
                                    DataCell(Text(server.loss)),
                                    DataCell(Text(server.rx)),
                                    DataCell(Text(server.tx)),
                                    DataCell(Text(server.tunnel)),
                                    DataCell(Text(server.nat)),
                                  ]);
                                }).toList(),
                              ),
                            )
                          else
                            const Text('暂无公共服务器连接', style: TextStyle(fontStyle: FontStyle.italic)),
                          if (_isEasyTierRunning && _servers.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 8.0),
                              child: Text('正在获取服务器数据...', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 64.0),
                ],
              ),
      ),
      floatingActionButton: _isServerRunning ? FloatingActionButton(
        onPressed:  _stopTcpServer,
        child: const Icon(Icons.stop),
      ) : null,
    );
  }
}