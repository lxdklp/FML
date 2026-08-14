import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fml/function/dio_client.dart';
import 'package:fml/function/log.dart';
import 'package:fml/function/launcher/login/microsoft_login.dart'
    as microsoft_login;

// 好友/好友请求条目
class FriendData {
  final String profileId;
  final String name;

  const FriendData({required this.profileId, required this.name});

  factory FriendData.fromJson(Map<String, dynamic> json) {
    return FriendData(
      profileId: json['profileId'] ?? '',
      name: json['name'] ?? '',
    );
  }
}

// 在线状态
class PresenceData {
  final String profileId;
  final String pmid;
  final String status;
  final bool invited;
  final String lastUpdated;

  const PresenceData({
    required this.profileId,
    required this.pmid,
    required this.status,
    required this.invited,
    required this.lastUpdated,
  });

  factory PresenceData.fromJson(Map<String, dynamic> json) {
    final joinInfo = json['joinInfo'];
    return PresenceData(
      profileId: json['profileId'] ?? '',
      pmid: json['pmid'] ?? '',
      status: json['status'] ?? 'OFFLINE',
      invited: joinInfo is Map && joinInfo['invited'] == true,
      lastUpdated: json['lastUpdated'] ?? '',
    );
  }
}

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  FriendsPageState createState() => FriendsPageState();
}

class FriendsPageState extends State<FriendsPage> {
  static const String _baseUrl = 'https://api.minecraftservices.com';

  bool _isOnlineAccount = false;
  bool _loading = true;
  String _error = '';
  String _token = '';
  String _etag = '';

  List<FriendData> _friends = [];
  List<FriendData> _incomingRequests = [];
  List<FriendData> _outgoingRequests = [];
  Map<String, PresenceData> _presence = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  // 初始化:检查当前所选账号是否为正版账号
  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    final prefs = await SharedPreferences.getInstance();
    final accountType = prefs.getString('SelectedAccountType') ?? '';
    if (accountType != '1') {
      setState(() {
        _isOnlineAccount = false;
        _loading = false;
      });
      return;
    }
    final accountName = prefs.getString('SelectedAccountName') ?? '';
    final accountInfo =
        prefs.getStringList('online_account_$accountName') ?? [];
    if (accountInfo.length < 3) {
      setState(() {
        _isOnlineAccount = true;
        _error = '找不到所选账号数据';
        _loading = false;
      });
      return;
    }
    setState(() {
      _isOnlineAccount = true;
    });
    // 参考正版登录流程获取当前所选账号的Authorization密钥
    final token = await microsoft_login.login(accountInfo[2]);
    if (token.isEmpty) {
      setState(() {
        _error = '登录失败,无法获取账号令牌';
        _loading = false;
      });
      return;
    }
    _token = token;
    await _loadFriends();
    await _reportPresence();
    setState(() {
      _loading = false;
    });
  }

  // 获取好友列表和好友请求
  Future<String> _loadFriends() async {
    try {
      final headers = <String, dynamic>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $_token',
      };
      if (_etag.isNotEmpty) {
        headers['If-None-Match'] = _etag;
      }
      final response = await DioClient().dio.get(
        '$_baseUrl/friends',
        options: Options(headers: headers),
      );
      if (response.statusCode == 200) {
        _etag = response.headers.value('ETag') ?? '';
        _applyFriendsResponse(response.data);
        return '';
      } else {
        LogUtil.log(
          '获取好友列表失败: 状态码: ${response.statusCode}, 响应: ${response.data}',
          level: 'ERROR',
        );
        return '获取好友列表失败: 状态码 ${response.statusCode}';
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 304) {
        LogUtil.log('好友列表未更改 (304 Not Modified)');
        return '';
      } else if (e.response?.statusCode == 401) {
        LogUtil.log('获取好友列表失败: 未授权 (401)', level: 'ERROR');
        return '未授权,请重新登录账号';
      } else {
        LogUtil.log(
          '获取好友列表异常: 状态码: ${e.response?.statusCode}, 消息: ${e.message}',
          level: 'ERROR',
        );
        return '获取好友列表失败: ${e.message}';
      }
    } catch (e) {
      LogUtil.log('获取好友列表发生其他错误: $e', level: 'ERROR');
      return '获取好友列表失败: $e';
    }
  }

  // 解析好友列表响应
  void _applyFriendsResponse(dynamic data) {
    if (data is! Map) return;
    setState(() {
      _friends = (data['friends'] as List? ?? [])
          .map((e) => FriendData.fromJson(e as Map<String, dynamic>))
          .toList();
      _incomingRequests = (data['incomingRequests'] as List? ?? [])
          .map((e) => FriendData.fromJson(e as Map<String, dynamic>))
          .toList();
      _outgoingRequests = (data['outgoingRequests'] as List? ?? [])
          .map((e) => FriendData.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  // 好友管理 (PUT /friends)
  // updateType: ADD 发送/接受好友请求, REMOVE 删除好友/拒绝好友请求
  Future<String> _manageFriend({
    String? name,
    String? profileId,
    required String updateType,
  }) async {
    final body = <String, dynamic>{'updateType': updateType};
    if (name != null && name.isNotEmpty) body['name'] = name;
    if (profileId != null && profileId.isNotEmpty) {
      body['profileId'] = profileId;
    }
    try {
      final response = await DioClient().dio.put(
        '$_baseUrl/friends',
        data: body,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $_token',
          },
        ),
      );
      if (response.statusCode == 200) {
        _etag = response.headers.value('ETag') ?? '';
        _applyFriendsResponse(response.data);
        return '';
      } else {
        LogUtil.log(
          '好友操作失败: 状态码: ${response.statusCode}, 响应: ${response.data}',
          level: 'ERROR',
        );
        return _parseErrorResponse(response.data, '好友操作失败');
      }
    } on DioException catch (e) {
      LogUtil.log(
        '好友操作异常: 状态码: ${e.response?.statusCode}, 消息: ${e.message}',
        level: 'ERROR',
      );
      if (e.response?.data != null) {
        return _parseErrorResponse(e.response!.data, '好友操作失败');
      }
      return '好友操作失败: ${e.message}';
    } catch (e) {
      LogUtil.log('好友操作发生其他错误: $e', level: 'ERROR');
      return '好友操作失败: $e';
    }
  }

  // 上报在线状态并获取好友在线状态 (POST /presence)
  Future<String> _reportPresence({String status = 'OFFLINE'}) async {
    try {
      final response = await DioClient().dio.post(
        '$_baseUrl/presence',
        data: {'status': status},
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $_token',
          },
        ),
      );
      if (response.statusCode == 200) {
        final presence = response.data is Map
            ? (response.data['presence'] as List? ?? [])
            : [];
        final map = <String, PresenceData>{};
        for (final item in presence) {
          if (item is Map<String, dynamic>) {
            final p = PresenceData.fromJson(item);
            map[p.profileId] = p;
          }
        }
        setState(() {
          _presence = map;
        });
        return '';
      } else {
        LogUtil.log(
          '上报在线状态失败: 状态码: ${response.statusCode}, 响应: ${response.data}',
          level: 'ERROR',
        );
        return _parseErrorResponse(response.data, '获取在线状态失败');
      }
    } on DioException catch (e) {
      LogUtil.log(
        '上报在线状态异常: 状态码: ${e.response?.statusCode}, 消息: ${e.message}',
        level: 'ERROR',
      );
      if (e.response?.data != null) {
        return _parseErrorResponse(e.response!.data, '获取在线状态失败');
      }
      return '获取在线状态失败: ${e.message}';
    } catch (e) {
      LogUtil.log('上报在线状态发生其他错误: $e', level: 'ERROR');
      return '获取在线状态失败: $e';
    }
  }

  // 解析API错误响应
  String _parseErrorResponse(dynamic data, String fallback) {
    try {
      if (data is Map) {
        final details = data['details'];
        if (details is Map) {
          final status = details['status'] ?? '';
          final message = details['errorMessage'] ?? '';
          if (message.isNotEmpty) return '$fallback: $message';
          if (status.isNotEmpty) return '$fallback: $status';
        }
        final message = data['errorMessage'];
        if (message is String && message.isNotEmpty) {
          return '$fallback: $message';
        }
      }
    } catch (e) {
      LogUtil.log('解析错误响应失败: $e', level: 'ERROR');
    }
    return fallback;
  }

  // 在线状态文本
  String _presenceLabel(String status, bool invited) {
    String label;
    switch (status) {
      case 'ONLINE':
        label = '在线';
        break;
      case 'PLAYING_OFFLINE':
        label = '在线 (世界)';
        break;
      case 'PLAYING_HOSTED_SERVER':
        label = '在线 (世界,可加入)';
        break;
      case 'PLAYING_REALMS':
        label = '在线 (领域服)';
        break;
      case 'PLAYING_SERVER':
        label = '在线 (服务器)';
        break;
      case 'OFFLINE':
      default:
        label = '离线';
        break;
    }
    if (invited) {
      label += ' · 邀请你加入';
    }
    return label;
  }

  // 添加好友对话框
  Future<void> _showAddFriendDialog() async {
    final nameController = TextEditingController();
    final uuidController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加好友'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '玩家名称',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: uuidController,
              decoration: const InputDecoration(
                labelText: 'UUID (可选,优先使用)',
                prefixIcon: Icon(Icons.tag),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (result != true) return;
    final name = nameController.text.trim();
    final profileId = uuidController.text.trim();
    if (name.isEmpty && profileId.isEmpty) {
      _showMessage('请填写玩家名称或UUID');
      return;
    }
    final error = await _manageFriend(
      name: name,
      profileId: profileId,
      updateType: 'ADD',
    );
    if (!mounted) return;
    if (error.isEmpty) {
      _showMessage('已发送好友请求');
    } else {
      _showMessage(error);
    }
  }

  // 确认对话框 (删除好友/拒绝请求/取消请求)
  Future<void> _confirmAction(FriendData friend, String actionText) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认操作'),
        content: Text('$actionText: ${friend.name} ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await _manageFriend(
      profileId: friend.profileId,
      updateType: 'REMOVE',
    );
    if (!mounted) return;
    if (error.isEmpty) {
      _showMessage('操作成功');
    } else {
      _showMessage(error);
    }
  }

  // 好友条目
  Widget _buildFriendTile(FriendData friend) {
    final presence = _presence[friend.profileId];
    String subtitle = friend.profileId;
    if (presence != null) {
      subtitle = _presenceLabel(presence.status, presence.invited);
    }
    return ListTile(
      leading: const Icon(Icons.person),
      title: Text(friend.name),
      subtitle: Text(subtitle),
      trailing: IconButton(
        icon: const Icon(Icons.person_remove, color: Colors.red),
        onPressed: () => _confirmAction(friend, '删除好友'),
      ),
    );
  }

  // 收到的好友请求条目
  Widget _buildIncomingTile(FriendData friend) {
    return ListTile(
      leading: const Icon(Icons.person_add),
      title: Text(friend.name),
      subtitle: Text(friend.profileId),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.green),
            onPressed: () async {
              final error = await _manageFriend(
                profileId: friend.profileId,
                updateType: 'ADD',
              );
              if (!mounted) return;
              error.isEmpty ? _showMessage('已接受好友请求') : _showMessage(error);
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () => _confirmAction(friend, '拒绝好友请求'),
          ),
        ],
      ),
    );
  }

  // 已发送的好友请求条目
  Widget _buildOutgoingTile(FriendData friend) {
    return ListTile(
      leading: const Icon(Icons.schedule),
      title: Text(friend.name),
      subtitle: Text(friend.profileId),
      trailing: IconButton(
        icon: const Icon(Icons.cancel, color: Colors.red),
        onPressed: () => _confirmAction(friend, '取消好友请求'),
      ),
    );
  }

  // 显示提示信息
  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // 刷新
  Future<void> _refresh() async {
    await _init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('好友列表'),
      ),
      body: !_isOnlineAccount
          ? const Center(child: Text('本功能仅限正版账号使用'))
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _error = '';
                      });
                      _init();
                    },
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  TabBar(
                    tabs: [
                      Tab(text: '好友 (${_friends.length})'),
                      Tab(text: '收到请求 (${_incomingRequests.length})'),
                      Tab(text: '已发送 (${_outgoingRequests.length})'),
                    ],
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _refresh,
                      child: TabBarView(
                        children: [
                          _friends.isEmpty
                              ? _buildEmptyList('暂无好友,点击右下角添加好友')
                              : ListView(
                                  children: _friends.map(_buildFriendTile).toList(),
                                ),
                          _incomingRequests.isEmpty
                              ? _buildEmptyList('暂无收到的好友请求')
                              : ListView(
                                  children: _incomingRequests
                                      .map(_buildIncomingTile)
                                      .toList(),
                                ),
                          _outgoingRequests.isEmpty
                              ? _buildEmptyList('暂无已发送的好友请求')
                              : ListView(
                                  children: _outgoingRequests
                                      .map(_buildOutgoingTile)
                                      .toList(),
                                ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: _isOnlineAccount && !_loading && _error.isEmpty
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton(
                  heroTag: 'refresh',
                  onPressed: _refresh,
                  tooltip: '刷新',
                  child: const Icon(Icons.refresh),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  onPressed: _showAddFriendDialog,
                  child: const Icon(Icons.person_add),
                ),
              ],
            )
          : null,
    );
  }

  // 空列表提示
  Widget _buildEmptyList(String text) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: constraints.maxHeight,
            child: Center(child: Text(text)),
          ),
        );
      },
    );
  }
}
