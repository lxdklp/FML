import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:fml/function/log.dart';

/// 联机协议TCP服务器
class OnlineCenterServer {
  ServerSocket? _server;
  final int port;
  final List<Socket> _clients = [];
  final List<PlayerProfile> _players = [];
  final int minecraftServerPort;
  final String hostName;
  final String hostVendor;
  OnlineCenterServer({
    required this.port,
    required this.minecraftServerPort,
    required this.hostName,
    required this.hostVendor,
  });
  List<PlayerProfile> get players => _players;

  // 将字节转换为无符号32位整数
  int _bytesToUint32(List<int> bytes) {
    if (bytes.length != 4) {
      throw ArgumentError('预期 4 个字节，实际 ${bytes.length}');
    }
    return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  }

  // 启动TCP服务器
  Future<void> start() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      LogUtil.log('TCP服务器启动在端口 $port', level: 'INFO');
      _server!.listen((socket) {
        _handleClient(socket);
      });
      return await Future.value();
    } catch (e) {
      LogUtil.log('TCP服务器启动失败: $e', level: 'ERROR');
      return Future.error(e);
    }
  }

  // 停止TCP服务器
  Future<void> stop() async {
    final clientsCopy = List<Socket>.from(_clients);
    for (var client in clientsCopy) {
      try {
        await _removeClient(client);
      } catch (e) {
        LogUtil.log('关闭客户端连接失败: $e', level: 'ERROR');
      }
    }
    _clients.clear();
    await _server?.close();
    _server = null;
    LogUtil.log('TCP服务器已关闭', level: 'INFO');
  }

  // 新客户端连接
  Future<void> _handleClient(Socket socket) async {
    final clientAddress = socket.remoteAddress.address;
    final clientPort = socket.remotePort;
    LogUtil.log('新客户端连接: $clientAddress:$clientPort', level: 'INFO');
    _clients.add(socket);
    List<int> buffer = [];
    int? expectedLength;
    socket.listen(
      (data) {
        if (!_clients.contains(socket)) {
          LogUtil.log('收到已移除客户端的数据，忽略', level: 'INFO');
          return;
        }
        buffer.addAll(data);
        while (buffer.isNotEmpty) {
          if (expectedLength == null) {
            if (buffer.isEmpty) return;
            final typeLength = buffer[0];
            if (buffer.length < 1 + typeLength + 4) return;
            final bodyLengthBytes = buffer.sublist(1 + typeLength, 5 + typeLength);
            final bodyLength = _bytesToUint32(bodyLengthBytes);
            expectedLength = 5 + typeLength + bodyLength;
            if (buffer.length < expectedLength!) return;
          }
          if (buffer.length >= expectedLength!) {
            final requestBytes = buffer.sublist(0, expectedLength!);
            buffer = buffer.sublist(expectedLength!);
            _handleRequest(requestBytes, socket).catchError((e) {
              LogUtil.log('处理请求异常: $e', level: 'ERROR');
            });
            expectedLength = null;
          } else {
            break;
          }
        }
      },
      onError: (error) {
        if (error is SocketException) {
          if (error.osError?.errorCode == 54) {
            LogUtil.log('客户端主动断开连接: $clientAddress:$clientPort', level: 'INFO');
          } else {
            LogUtil.log('客户端连接错误 [${error.osError?.errorCode}]: $error', level: 'WARNING');
          }
        } else {
          LogUtil.log('客户端连接错误: $error', level: 'ERROR');
        }
        _removeClient(socket, clientAddress, clientPort);
      },
      onDone: () {
        LogUtil.log('客户端连接关闭: $clientAddress:$clientPort', level: 'INFO');
        _removeClient(socket, clientAddress, clientPort);
      },
      cancelOnError: false,
    );
  }

  // 移除客户端
  Future<void> _removeClient(Socket socket, [String? savedAddress, int? savedPort]) async {
    if (!_clients.contains(socket)) {
      return;
    }
    String clientId;
    try {
      clientId = savedAddress != null && savedPort != null
          ? '$savedAddress:$savedPort'
          : '${socket.remoteAddress.address}:${socket.remotePort}';
    } catch (e) {
      clientId = 'unknown-client';
      LogUtil.log('获取客户端地址失败: $e', level: 'INFO');
    }
    _clients.remove(socket);
    try {
      await socket.close();
    } catch (e) {
      LogUtil.log('关闭socket失败: $e', level: 'ERROR');
    }
    _players.removeWhere((player) {
      final isMatch = player.socketId == clientId;
      if (isMatch) {
        LogUtil.log('玩家离线: ${player.name}', level: 'INFO');
      }
      return isMatch;
    });
  }

  // 处理客户端请求
  Future<void> _handleRequest(List<int> requestBytes, Socket socket) async {
    if (!_clients.contains(socket)) {
      LogUtil.log('尝试处理已断开连接的客户端请求', level: 'WARNING');
      return;
    }
    try {
      final typeLength = requestBytes[0];
      final requestTypeBytes = requestBytes.sublist(1, 1 + typeLength);
      final requestType = utf8.decode(requestTypeBytes);
      final bodyLengthBytes = requestBytes.sublist(1 + typeLength, 5 + typeLength);
      final bodyLength = _bytesToUint32(bodyLengthBytes);
      final body = bodyLength > 0
          ? requestBytes.sublist(5 + typeLength, (5 + typeLength + bodyLength) as int?)
          : <int>[];
      LogUtil.log('收到请求: $requestType, 请求体长度: $bodyLength', level: 'INFO');
      if (!_clients.contains(socket)) {
        LogUtil.log('请求处理过程中客户端断开: $requestType', level: 'WARNING');
        return;
      }
      // 根据请求类型分发处理
      switch (requestType) {
        case 'c:ping':
          await _handlePingRequest(body, socket);
          break;
        case 'c:protocols':
          await _handleProtocolsRequest(body, socket);
          break;
        case 'c:server_port':
          await _handleServerPortRequest(body, socket);
          break;
        case 'c:player_ping':
          await _handlePlayerPingRequest(body, socket);
          break;
        case 'c:player_profiles_list':
          await _handlePlayerProfilesListRequest(body, socket);
          break;
        default:
          await _sendErrorResponse(socket, 255, 'Unknown protocol: $requestType');
          break;
      }
    } catch (e, stack) {
      LogUtil.log('处理请求失败: $e\n$stack', level: 'ERROR');
      if (_clients.contains(socket)) {
        await _sendErrorResponse(socket, 255, 'Error processing request: $e');
      }
    }
  }

  // 处理 c:ping 请求
  Future<void> _handlePingRequest(List<int> body, Socket socket) async {
    _sendSuccessResponse(socket, body);
  }

  // 处理 c:protocols 请求
  Future<void> _handleProtocolsRequest(List<int> body, Socket socket) async {
    // 支持的协议列表
    final supportedProtocols = [
      'c:protocols',
      'c:ping',
      'c:server_port',
      'c:player_ping',
      'c:player_profile_list',
      'c:player_easytier_id',
    ];
    final responseBody = utf8.encode(supportedProtocols.join('0'));
    _sendSuccessResponse(socket, responseBody);
  }

  // 处理 c:server_port 请求
  Future<void> _handleServerPortRequest(List<int> body, Socket socket) async {
    if (minecraftServerPort <= 0) {
      LogUtil.log('服务器端口请求失败: 端口号无效 ($minecraftServerPort)', level: 'WARNING');
      _sendErrorResponse(socket, 32, '');
      return;
    }
    LogUtil.log('发送Minecraft服务器端口: $minecraftServerPort 到客户端: ${socket.remoteAddress.address}:${socket.remotePort}', level: 'INFO');
    final portBytes = Uint8List(2);
    portBytes[0] = (minecraftServerPort >> 8) & 0xFF;
    portBytes[1] = minecraftServerPort & 0xFF;
    _sendSuccessResponse(socket, portBytes);
  }

  // 处理 c:player_ping 请求
  Future<void> _handlePlayerPingRequest(List<int> body, Socket socket) async {
    try {
      final jsonString = utf8.decode(body);
      final data = jsonDecode(jsonString);
      final name = data['name'] as String;
      final machineId = data['machine_id'] as String;
      final easytierId = (data['easytier_id'] as String?) ?? '';
      final vendor = data['vendor'] as String;
      final socketId = '${socket.remoteAddress.address}:${socket.remotePort}';
      final existingPlayerIndex = _players.indexWhere((p) => p.machineId == machineId);
      if (existingPlayerIndex >= 0) {
        _players[existingPlayerIndex].lastActivity = DateTime.now();
        _players[existingPlayerIndex].socketId = socketId;
        if (easytierId.isNotEmpty) {
          _players[existingPlayerIndex].easytierId = easytierId;
        }
      } else {
        _players.add(PlayerProfile(
          name: name,
          machineId: machineId,
          easytierId: easytierId,
          vendor: vendor,
          kind: 'GUEST',
          socketId: socketId,
        ));
      }
      _sendSuccessResponse(socket, []);
    } catch (e) {
      LogUtil.log('处理player_ping失败: $e', level: 'ERROR');
      _sendErrorResponse(socket, 255, 'Invalid player_ping format: $e');
    }
  }

  // 处理 c:player_profiles_list 请求
  Future<void> _handlePlayerProfilesListRequest(List<int> body, Socket socket) async {
    // 清理超时玩家（30秒无心跳）
    final now = DateTime.now();
    _players.removeWhere((player) {
      if (player.kind == 'HOST') return false;
      final isTimeout = now.difference(player.lastActivity).inSeconds > 30;
      if (isTimeout) {
        LogUtil.log('玩家超时: ${player.name}', level: 'INFO');
      }
      return isTimeout;
    });
    final allPlayers = _players.map((p) => {
      'name': p.name,
      'machine_id': p.machineId,
      'easytier_id': p.easytierId,
      'vendor': p.vendor,
      'kind': p.kind
    }).toList();
    final responseBody = utf8.encode(jsonEncode(allPlayers));
    _sendSuccessResponse(socket, responseBody);
  }

  // 发送成功响应
  Future<void> _sendSuccessResponse(Socket socket, List<int> body) async {
    final response = _buildResponse(0, body);
    _sendResponse(socket, response);
  }

  // 发送错误响应
  Future<void> _sendErrorResponse(Socket socket, int status, String message) async{
    final body = message.isNotEmpty ? utf8.encode(message) : <int>[];
    final response = _buildResponse(status, body);
    _sendResponse(socket, response);
  }
  // 构建响应
  Uint8List _buildResponse(int status, List<int> body) {
    final bodyLength = body.length;
    // 创建响应缓冲区：1字节状态 + 4字节长度 + 正文
    final buffer = Uint8List(5 + bodyLength);
    buffer[0] = status;
    buffer[1] = (bodyLength >> 24) & 0xFF;
    buffer[2] = (bodyLength >> 16) & 0xFF;
    buffer[3] = (bodyLength >> 8) & 0xFF;
    buffer[4] = bodyLength & 0xFF;
    if (bodyLength > 0) {
      buffer.setRange(5, 5 + bodyLength, body);
    }
    return buffer;
  }

  // 发送响应
  Future<void> _sendResponse(Socket socket, List<int> response) async {
    if (!_clients.contains(socket)) {
      LogUtil.log('尝试向已关闭的socket发送数据', level: 'WARNING');
      return;
    }
    try {
      socket.add(response);
      await Future.microtask(() async {
        try {
          await socket.flush().timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              LogUtil.log('发送响应超时，但不断开连接', level: 'WARNING');
            },
          );
          LogUtil.log('成功发送响应, ${response.length}字节', level: 'INFO');
        } catch (e) {
          LogUtil.log('flush时出现错误: $e', level: 'INFO');
        }
      });
    } on SocketException catch (e) {
      final errorCode = e.osError?.errorCode;
      if (errorCode == 54 || errorCode == 32 || errorCode == 57 || errorCode == 104) {
        LogUtil.log('发送响应失败,连接已断开 [错误码: $errorCode]: ${e.message}', level: 'INFO');
        await _removeClient(socket);
      } else {
        LogUtil.log('发送响应时出现socket异常 [错误码: $errorCode]: $e', level: 'WARNING');
      }
    } on StateError catch (e) {
      LogUtil.log('socket状态错误: $e ,数据可能已发送', level: 'INFO');
    } catch (e) {
      LogUtil.log('发送响应时出现错误: $e, 类型: ${e.runtimeType}', level: 'WARNING');
    }
  }

  // 生成并添加主机玩家
  Future<void> addHostPlayer(String machineId, String easytierId) async {
    _players.add(PlayerProfile(
      name: hostName,
      machineId: machineId,
      easytierId: easytierId,
      vendor: hostVendor,
      kind: 'HOST',
      socketId: 'local-host',
    ));
    LogUtil.log('添加房主: $hostName ($hostVendor) easytierID: $easytierId, machineID: $machineId', level: 'INFO');
  }
}

/// 玩家信息
class PlayerProfile {
  final String name;
  final String machineId;
  final String vendor;
  final String kind; // 'HOST' | 'GUEST'
  String easytierId;
  DateTime lastActivity;
  String socketId;
  PlayerProfile({
    required this.name,
    required this.machineId,
    required this.easytierId,
    required this.vendor,
    required this.kind,
    required this.socketId,
    DateTime? lastActivity,
  }) : lastActivity = lastActivity ?? DateTime.now();
}