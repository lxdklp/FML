import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:fml/function/log.dart';

/// Scaffolding协议TCP客户端
class OnlineCenterClient {
  Socket? _socket;
  final String serverAddress;
  final int serverPort;
  final String playerName;
  final String machineId;
  final String easytierId;
  final String vendor;
  bool _isConnected = false;
  Timer? _heartbeatTimer;
  int? _minecraftServerPort;
  List<String> _supportedProtocols = [];
  final List<PlayerProfile> _players = [];
  final StreamController<List<PlayerProfile>> _playersStreamController = StreamController<List<PlayerProfile>>.broadcast();
  final StreamController<int?> _minecraftPortStreamController = StreamController<int?>.broadcast();
  final StreamController<bool> _serverDisconnectedStreamController = StreamController<bool>.broadcast();
  int _connectionAttempts = 0;
  final int _maxConnectionAttempts = 3;
  bool _isConnecting = false;
  final bool useIP;
  int _missedHeartbeats = 0;
  final int _maxMissedHeartbeats = 3;
  DateTime? _lastHeartbeatResponse;

  OnlineCenterClient({
    required this.serverAddress,
    required this.serverPort,
    required this.playerName,
    required this.machineId,
    this.easytierId = '',
    this.vendor = 'FML',
    this.useIP = false,
  });

  List<PlayerProfile> get players => _players;
  bool get isConnected => _isConnected;
  int? get minecraftServerPort => _minecraftServerPort;
  Stream<List<PlayerProfile>> get playersStream => _playersStreamController.stream;
  Stream<int?> get minecraftPortStream => _minecraftPortStreamController.stream;
  Stream<bool> get serverDisconnectedStream => _serverDisconnectedStreamController.stream;

  // 连接到服务器并开始心跳
  Future<void> connect() async {
    if (_isConnected) return;
    if (_isConnecting) {
      LogUtil.log('已有一个连接请求在进行中', level: 'WARNING');
      return;
    }
    _isConnecting = true;
    _connectionAttempts++;
    try {
      String formattedHost = serverAddress;
      if (!useIP && !formattedHost.startsWith('scaffolding-mc-server-')) {
        LogUtil.log('警告: 主机名 "$formattedHost" 不符合预期格式 "scaffolding-mc-server-$serverPort"', level: 'WARNING');
      }
      String connectionType = useIP ? "IP" : "主机名";
      LogUtil.log('正在连接到联机中心: $formattedHost:$serverPort (使用$connectionType, 尝试 $_connectionAttempts/$_maxConnectionAttempts)', level: 'INFO');
      _socket = await Socket.connect(formattedHost, serverPort).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('连接超时');
        }
      );
      _isConnected = true;
      _isConnecting = false;
      LogUtil.log('已连接到联机中心: $formattedHost:$serverPort', level: 'INFO');
      _startListening();
      await _negotiateProtocols();
      await Future.delayed(const Duration(milliseconds: 100));
      await _sendPlayerPing();
      _startHeartbeat();
      return await Future.value();
    } catch (e) {
      _isConnected = false;
      _isConnecting = false;
      LogUtil.log('连接联机中心失败: $e', level: 'ERROR');
      if (_connectionAttempts < _maxConnectionAttempts) {
        LogUtil.log('将在2秒后自动重试连接', level: 'INFO');
        await Future.delayed(const Duration(seconds: 2));
        return connect();
      }
      return Future.error(e);
    }
  }

  // 断开连接并清理资源
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _isConnected = false;
    _isConnecting = false;
    _connectionAttempts = 0;
    _missedHeartbeats = 0;
    _lastHeartbeatResponse = null;
    try {
      await _socket?.close();
      _socket = null;
      LogUtil.log('已断开与联机中心的连接', level: 'INFO');
    } catch (e) {
      LogUtil.log('断开连接时出错: $e', level: 'ERROR');
    }
  }

  // 开始监听服务器响应
  Future<void> _startListening() async {
    List<int> buffer = [];
    int? expectedLength;
    _socket!.listen(
      (data) {
        LogUtil.log('收到原始数据: ${data.length}字节', level: 'INFO');
        buffer.addAll(data);
        while (buffer.isNotEmpty) {
          if (expectedLength == null) {
            if (buffer.length < 5) {
              return;
            }
            final bodyLengthBytes = buffer.sublist(1, 5);
            final bodyLength = _bytesToUint32(bodyLengthBytes);
            expectedLength = 5 + bodyLength;
            if (buffer.length < expectedLength!) {
              return;
            }
          }
          if (buffer.length >= expectedLength!) {
            final response = buffer.sublist(0, expectedLength!);
            buffer = buffer.sublist(expectedLength!);
            _handleResponse(response);
            expectedLength = null;
          }
        }
      },
      onError: (error) {
        LogUtil.log('联机中心连接错误: $error', level: 'ERROR');
        _handleDisconnect();
      },
      onDone: () {
        LogUtil.log('联机中心连接关闭', level: 'INFO');
        _handleDisconnect();
      },
      cancelOnError: false,
    );
  }

  // 获取Minecraft服务器端口
  Future<void> getMinecraftServerPort() async {
    await _getMinecraftServerPort();
  }

  // 处理连接断开
  Future<void> _handleDisconnect() async {
    if (!_isConnected) return;
    _isConnected = false;
    _isConnecting = false;
    _heartbeatTimer?.cancel();
    try {
      await _socket?.close();
    } catch (e) {
      LogUtil.log('关闭socket时出错: $e', level: 'ERROR');
    }
    _socket = null;
    LogUtil.log('连接已断开', level: 'WARNING');
  }

  // 处理服务器响应
  Future<void> _handleResponse(List<int> response) async {
    try {
      final status = response[0];
      final bodyLengthBytes = response.sublist(1, 5);
      final bodyLength = _bytesToUint32(bodyLengthBytes);
      final body = bodyLength > 0
          ? response.sublist(5, 5 + bodyLength)
          : <int>[];
      LogUtil.log('处理响应: 状态=$status, body长度=$bodyLength', level: 'INFO');
      if (status == 0) {
        _handleSuccessResponse(body);
      } else if (status == 32) {
        LogUtil.log('服务器未启动Minecraft服务 (状态码 32)', level: 'WARNING');
        _minecraftPortStreamController.add(null);
      } else {
        final errorMessage = bodyLength > 0 ? utf8.decode(body) : '未知错误';
        LogUtil.log('联机中心返回错误(状态码 $status): $errorMessage', level: 'ERROR');
      }
    } catch (e) {
      LogUtil.log('处理响应时出错: $e', level: 'ERROR');
    }
  }

  // 处理成功响应
  Future<void> _handleSuccessResponse(List<int> body) async {
    if (body.isEmpty) {
      _lastHeartbeatResponse = DateTime.now();
      _missedHeartbeats = 0;
      return;
    }
    try {
      final jsonString = utf8.decode(body);
      LogUtil.log('收到响应数据: $jsonString', level: 'INFO');
      if (jsonString.startsWith('[')) {
        _handlePlayerProfilesList(jsonString);
        return;
      }
      if (jsonString.contains('0')) {
        _handleProtocolsResponse(jsonString);
        return;
      }
    } catch (_) {
    }
    if (body.length == 2) {
      _handleServerPortResponse(body);
      return;
    }
    LogUtil.log('收到未识别的成功响应: ${body.length}字节', level: 'INFO');
  }

  // 处理协议列表响应
  Future<void> _handleProtocolsResponse(String response) async {
    try {
      final protocols = response.split('0');
      _supportedProtocols = protocols.where((p) => p.isNotEmpty).toList();
      LogUtil.log('服务端支持的协议: $_supportedProtocols', level: 'INFO');
      if (_supportedProtocols.contains('c:player_easytier_id')) {
        LogUtil.log('服务端支持 c:player_easytier_id 协议,心跳将包含EasyTier ID', level: 'INFO');
      } else {
        LogUtil.log('服务端不支持 c:player_easytier_id 协议,心跳将使用旧格式', level: 'WARNING');
      }
    } catch (e) {
      LogUtil.log('解析协议列表失败: $e', level: 'ERROR');
    }
  }

  // 处理Minecraft服务器端口响应
  Future<void> _handleServerPortResponse(List<int> body) async {
    if (body.length == 2) {
      final port = (body[0] << 8) | body[1];
      _minecraftServerPort = port;
      _minecraftPortStreamController.add(port);
      LogUtil.log('Minecraft服务器端口: $_minecraftServerPort', level: 'INFO');
    }
  }

  // 处理玩家列表响应
  Future<void> _handlePlayerProfilesList(String jsonString) async {
    try {
      final List<dynamic> playersJson = jsonDecode(jsonString);
      _players.clear();
      for (var playerJson in playersJson) {
        _players.add(PlayerProfile(
          name: playerJson['name'],
          machineId: playerJson['machine_id'],
          easytierId: playerJson['easytier_id'] ?? '',
          vendor: playerJson['vendor'],
          kind: playerJson['kind'],
        ));
      }
      _playersStreamController.add(_players);
      LogUtil.log('收到玩家列表, 共 ${_players.length} 名玩家', level: 'INFO');
    } catch (e) {
      LogUtil.log('解析玩家列表失败: $e, 原始JSON: $jsonString', level: 'ERROR');
    }
  }

  // 启动定时心跳和玩家列表获取
  Future<void> _startHeartbeat() async {
    _heartbeatTimer?.cancel();
    _lastHeartbeatResponse = DateTime.now();
    _missedHeartbeats = 0;
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_isConnected) return;
      try {
        await _sendPlayerPing();
        await _getPlayerProfilesList();
        final now = DateTime.now();
        if (_lastHeartbeatResponse != null) {
          final timeSinceLastResponse = now.difference(_lastHeartbeatResponse!).inSeconds;
          if (timeSinceLastResponse > 15) {
            _missedHeartbeats++;
            LogUtil.log('心跳超时 (已连续$_missedHeartbeats次), 距上次响应: $timeSinceLastResponse秒', level: 'WARNING');
            if (_missedHeartbeats >= _maxMissedHeartbeats) {
              LogUtil.log('连续$_maxMissedHeartbeats次心跳无响应,判定服务器已断开', level: 'ERROR');
              _serverDisconnectedStreamController.add(true);
              await _handleDisconnect();
            }
          }
        }
      } catch (e) {
        LogUtil.log('发送心跳失败: $e', level: 'ERROR');
        _missedHeartbeats++;
        if (_missedHeartbeats >= _maxMissedHeartbeats) {
          LogUtil.log('连续$_maxMissedHeartbeats次心跳发送失败,判定服务器已断开', level: 'ERROR');
          _serverDisconnectedStreamController.add(true);
          await _handleDisconnect();
        }
      }
    });
  }

  // 协议协商，获取服务器支持的协议
  Future<void> _negotiateProtocols() async {
    if (!_isConnected) return;
    try {
      await _sendRequest('c:protocols', []);
      LogUtil.log('已发送协议协商请求', level: 'INFO');
    } catch (e) {
      LogUtil.log('协议协商失败: $e', level: 'ERROR');
    }
  }

  // 获取Minecraft服务器端口
  Future<void> _getMinecraftServerPort() async {
    if (!_isConnected) return;
    try {
      await _sendRequest('c:server_port', []);
      LogUtil.log('已发送获取Minecraft服务器端口请求', level: 'INFO');
    } catch (e) {
      LogUtil.log('获取Minecraft服务器端口失败: $e', level: 'ERROR');
    }
  }

    // 发送玩家心跳
  Future<void> _sendPlayerPing() async {
    if (!_isConnected) return;
    try {
      final Map<String, dynamic> pingData;
      if (_supportedProtocols.contains('c:player_easytier_id')) {
        pingData = {
          'name': playerName,
          'machine_id': machineId,
          'easytier_id': easytierId,
          'vendor': vendor,
        };
      } else {
        pingData = {
          'name': playerName,
          'machine_id': machineId,
          'vendor': vendor,
        };
      }
      final jsonData = utf8.encode(jsonEncode(pingData));
      await _sendRequest('c:player_ping', jsonData);
      LogUtil.log('已发送心跳包', level: 'INFO');
    } catch (e) {
      LogUtil.log('发送心跳包失败: $e', level: 'ERROR');
      rethrow;
    }
  }

  // 获取玩家列表
  Future<void> _getPlayerProfilesList() async {
    if (!_isConnected) return;
    try {
      await _sendRequest('c:player_profiles_list', []);
      LogUtil.log('已请求玩家列表', level: 'INFO');
    } catch (e) {
      LogUtil.log('请求玩家列表失败: $e', level: 'ERROR');
      rethrow;
    }
  }

  // 发送请求
  Future<void> _sendRequest(String requestType, List<int> body) async {
    if (!_isConnected || _socket == null) {
      throw Exception('未连接到服务器');
    }
    try {
      final request = _buildRequest(requestType, body);
      _socket!.add(request);
      await _socket!.flush();
      LogUtil.log('已发送请求: $requestType, ${body.length}字节', level: 'INFO');
    } catch (e) {
      LogUtil.log('发送请求失败: $e, 类型: $requestType', level: 'ERROR');
      if (e.toString().contains('Broken pipe') ||
          e.toString().contains('Connection reset') ||
          e.toString().contains('Connection closed')) {
        await _handleDisconnect();
      }
      rethrow;
    }
  }

  // 构建请求
  Uint8List _buildRequest(String requestType, List<int> body) {
    final requestTypeBytes = utf8.encode(requestType);
    final typeLength = requestTypeBytes.length;
    if (typeLength > 255) {
      throw Exception('请求类型过长');
    }
    final bodyLength = body.length;
    // 创建请求缓冲区：1字节类型长度 + 类型字节 + 4字节body长度 + body内容
    final buffer = Uint8List(1 + typeLength + 4 + bodyLength);
    buffer[0] = typeLength;
    buffer.setRange(1, 1 + typeLength, requestTypeBytes);
    buffer[1 + typeLength] = (bodyLength >> 24) & 0xFF;
    buffer[2 + typeLength] = (bodyLength >> 16) & 0xFF;
    buffer[3 + typeLength] = (bodyLength >> 8) & 0xFF;
    buffer[4 + typeLength] = bodyLength & 0xFF;
    if (bodyLength > 0) {
      buffer.setRange(5 + typeLength, 5 + typeLength + bodyLength, body);
    }
    return buffer;
  }

  int _bytesToUint32(List<int> bytes) {
    return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  }
}

// 玩家信息
class PlayerProfile {
  final String name;
  final String machineId;
  final String easytierId;
  final String vendor;
  final String kind; // 'HOST' | 'GUEST'
  DateTime lastActivity;

  PlayerProfile({
    required this.name,
    required this.machineId,
    required this.easytierId,
    required this.vendor,
    required this.kind,
    DateTime? lastActivity,
  }) : lastActivity = lastActivity ?? DateTime.now();
}
