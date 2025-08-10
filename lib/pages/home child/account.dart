import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fml/pages/home child/account child/NewAccount.dart';
import 'package:fml/pages/home child/account child/AccountManagement.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  _AccountPageState createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  List<String> _accounts = [];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

// 读取本地账号列表
  Future<void> _loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _accounts = prefs.getStringList('AccountsList') ?? [];
    });
  }

// 账号信息
  Future<Map<String, String>> _getAccountInfo(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final uuid = prefs.getStringList('Account_$name')?[0] ?? '';
    final online = prefs.getStringList('Account_$name')?[1] ?? '';
    final isCustomUUID = prefs.getStringList('Account_$name')?[2] ?? '';
    final customUUID = prefs.getStringList('Account_$name')?[3] ?? '';
    return {'uuid': uuid, 'online': online, 'isCustomUUID': isCustomUUID, 'customUUID': customUUID};
  }

// 跳转添加账号页并在返回后刷新
  Future<void> _addAccount() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NewAccountPage()),
    );
    _loadAccounts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('账号管理'),
      ),
      body: _accounts.isEmpty
          ? const Center(child: Text('暂无账号'))
          : ListView.builder(
              itemCount: _accounts.length,
              itemBuilder: (context, index) {
                return FutureBuilder<Map<String, String>>(
                  future: _getAccountInfo(_accounts[index]),
                  builder: (context, snapshot) {
                    String _uuid = snapshot.data?['uuid'] ?? '';
                    String _online = snapshot.data?['online'] ?? '';
                    String _isCustomUUID = snapshot.data?['isCustomUUID'] ?? '';
                    String _customUUID = snapshot.data?['customUUID'] ?? '';
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: const Icon(Icons.account_circle),
                        title: Text(_accounts[index]),
                        subtitle: Text('生成UUID: $_uuid\n'
                            '${_isCustomUUID == '1' ? '已启用自定义UUID: $_customUUID' : '未启用自定义UUID'}\n'
                            '${_online == 'true' ? '正版账号' : '离线账号'}'),
                        onTap: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('SelectedAccount', _accounts[index]);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('已切换账号: ${_accounts[index]}')),
                          );
                          Navigator.pop(context);
                        },
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AccountManagementPage(accountName: _accounts[index]),
                          ),
                        ).then((_) => _loadAccounts());
                      },
                    ),
                  ),
                );
                },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addAccount,
        child: const Icon(Icons.add),
      ),
    );
  }
}