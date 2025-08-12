import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountManagementPage extends StatefulWidget {
  final String accountName;
  const AccountManagementPage({super.key, required this.accountName});

  @override
  _AccountManagementPageState createState() => _AccountManagementPageState();
}

class _AccountManagementPageState extends State<AccountManagementPage> {
  String _uuid = '';
  bool _online = false;
  bool _isCustomUUID = false;
  String _customUUID = '';
  bool _loading = true;

  // 校验
  bool _isValidUUID(String value) {
    final reg = RegExp(r'^[a-z0-9]{32}$');
    return reg.hasMatch(value);
  }

  final TextEditingController _customUUIDController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAccountInfo();
  }

  @override
  void dispose() {
    _customUUIDController.dispose();
    super.dispose();
  }

  // 读取账号信息
  Future<Map<String, String>> _getAccountInfo(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('Account_$name') ?? [];
    while (list.length < 4) {
      list.add('');
    }
    return {
      'uuid': list[0],
      'online': list[1],
      'isCustomUUID': list[2],
      'customUUID': list[3],
    };
  }
  Future<void> _loadAccountInfo() async {
    final info = await _getAccountInfo(widget.accountName);
    setState(() {
      _uuid = info['uuid'] ?? '';
      _online = (info['online'] == 'true');
      _isCustomUUID = (info['isCustomUUID'] == '1');
      _customUUID = info['customUUID'] ?? '';
      if (_isCustomUUID) {
        _customUUIDController.text = _customUUID;
      }
      _loading = false;
    });
  }

  // 保存账号信息
  Future<void> _saveAccountInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final list = [
      _uuid,
      _online.toString(),
      _isCustomUUID ? '1' : '0',
      _isCustomUUID ? _customUUIDController.text : '',
    ];
    await prefs.setStringList('Account_${widget.accountName}', list);
  }

  // 删除账号
  Future<void> _deleteAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = prefs.getStringList('AccountsList') ?? [];
    accounts.remove(widget.accountName);
    await prefs.setStringList('AccountsList', accounts);
    await prefs.remove('Account_${widget.accountName}');
    if (widget.accountName == prefs.getString('SelectedAccount')) {
      await prefs.remove('SelectedAccount');
    }
    if (!mounted) return;
    Navigator.pop(context); // 关闭对话框
    Navigator.pop(context); // 返回上一页
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除账号: ${widget.accountName}')),
    );
  }

  // 删除账号提示框
  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除账号'),
        content: Text('确定删除账号 ${widget.accountName} ？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            TextButton(
            onPressed: _deleteAccount,
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // 基础信息
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: const Icon(Icons.account_circle),
            title: Text(widget.accountName),
            subtitle: Text(
              '类型: ${_online ? "正版" : "离线"}\n'
              'UUID: ${_isCustomUUID && _customUUID.isNotEmpty ? _customUUID : _uuid}',
            ),
          ),
        ),
        // 自定义 UUID
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('使用自定义 UUID'),
                  value: _isCustomUUID,
                  onChanged: (v) async {
                    setState(() {
                      _isCustomUUID = v;
                      if (!v) {
                        _customUUIDController.clear();
                      } else {
                        _customUUIDController.text = _customUUID;
                      }
                    });
                    await _saveAccountInfo();
                  },
                ),
                if (_isCustomUUID)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _customUUIDController,
                      maxLength: 32,
                      decoration:  InputDecoration(
                        labelText: '自定义 UUID',
                        hintText: _uuid,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) async {
                        _customUUID = val;
                        if (_isValidUUID(val)){
                          await _saveAccountInfo();
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('账号管理')),
      body: _buildBody(),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'save',
            onPressed: () async {
              if (_isCustomUUID) {
                final value = _customUUIDController.text;
                if (!_isValidUUID(value)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('无效的自定义 UUID:应为32位小写字母或数字')),
                  );
                  return;
                }
                _customUUID = value;
              }
              await _saveAccountInfo();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已保存账号信息')),
              );
            },
            child: const Icon(Icons.save),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'delete',
            onPressed: _showDeleteDialog,
            child: const Icon(Icons.delete),
          ),
        ],
      ),
    );
  }
}