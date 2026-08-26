import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fml/function/log.dart';

class OfflineAccountManagementPage extends StatefulWidget {
  final String accountName;
  const OfflineAccountManagementPage({super.key, required this.accountName});

  @override
  OfflineAccountManagementPageState createState() => OfflineAccountManagementPageState();
}

class OfflineAccountManagementPageState extends State<OfflineAccountManagementPage> {
  String _uuid = '';
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
    final list = prefs.getStringList('offline_account_$name') ?? [];
    if (list.isEmpty) {
      return {
        'uuid': '',
        'isCustomUUID': '0',
        'customUUID': '',
      };
    }
    return {
      'uuid': list[1],
      'isCustomUUID': list[2],
      'customUUID': list[3],
    };
  }

  Future<void> _loadAccountInfo() async {
    final info = await _getAccountInfo(widget.accountName);
    setState(() {
      _uuid = info['uuid'] ?? '';
      _isCustomUUID = (info['isCustomUUID'] == '1');
      _customUUID = info['customUUID'] ?? '';
      // 设置输入框的值
      if (_isCustomUUID && _customUUID.isNotEmpty) {
        _customUUIDController.text = _customUUID;
      }
      _loading = false;
    });
  }

  // 保存账号信息
  Future<void> _saveAccountInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final list = [
      '0',  // 登录模式
      _isCustomUUID ? _uuid : _uuid, // 保持原始UUID不变
      _isCustomUUID ? '1' : '0',     // 是否自定义UUID
      _customUUIDController.text,    // 自定义UUID值
    ];
    await prefs.setStringList('offline_account_${widget.accountName}', list);
    LogUtil.log('保存${widget.accountName}', level: 'INFO');
  }
  // 删除账号
  Future<void> _deleteAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = prefs.getStringList('offline_accounts_list') ?? [];
    accounts.remove(widget.accountName);
    await prefs.setStringList('offline_accounts_list', accounts);
    await prefs.remove('offline_account_${widget.accountName}');
    if (widget.accountName == prefs.getString('SelectedAccount')) {
      await prefs.remove('SelectedAccount');
    }
    LogUtil.log('已删除账号: ${widget.accountName}', level: 'INFO');
    if (!mounted) return;
    Navigator.pop(context);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除账号: ${widget.accountName}')),
    );
  }

  // 删除账号提示框
  Future<void> _showDeleteDialog() async {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除账号'),
        content: Text('确定删除账号 ${widget.accountName} ?'),
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
            subtitle: Text('当前UUID: ${_isCustomUUID ? _customUUID : _uuid}'),
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
                  onChanged: (value) async {
                    setState(() {
                      _isCustomUUID = value;
                      // 关闭时保持原有自定义UUID值，只是不使用它
                      if (value) {
                        _customUUIDController.text = _customUUID.isEmpty ? _uuid : _customUUID;
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