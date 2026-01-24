import 'package:flutter/material.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fml/function/log.dart';
import 'package:fml/pages/home/account/new_account.dart';
import 'package:fml/pages/home/account/offline_account_management.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  AccountPageState createState() => AccountPageState();
}

class AccountPageState extends State<AccountPage> {
  List<String> _offlineAccounts = [];
  List<String> _onlineAccounts = [];
  List<String> _externalAccounts = [];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  // 读取本地账号列表
  Future<void> _loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _offlineAccounts = prefs.getStringList('offline_accounts_list') ?? [];
      _onlineAccounts = prefs.getStringList('online_accounts_list') ?? [];
      _externalAccounts = prefs.getStringList('external_accounts_list') ?? [];
    });
  }

  // 账号信息
  Future<Map<String, dynamic>> _getAccountInfo(String name, String type) async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? accountData;
    switch (type) {
      case '0':
        accountData = prefs.getStringList('offline_account_$name');
        break;
      case '1':
        accountData = prefs.getStringList('online_account_$name');
        break;
      case '2':
        accountData = prefs.getStringList('external_account_$name');
        break;
    }
    if (accountData == null || accountData.isEmpty) {
      return {'error': '找不到账号数据'};
    }

    // 基本信息
    Map<String, dynamic> info = {'loginMode': type, 'uuid': accountData[1]};
    switch (type) {
      case '0':
        info['isCustomUUID'] = accountData[2];
        info['customUUID'] = accountData[3];
        if (accountData[2] == '1' && accountData[3].isNotEmpty) {
          info['uuid'] = accountData[3];
        }
        break;
      case '1':
        break;
      case '2':
        info['serverUrl'] = accountData[2];
        info['username'] = accountData[3];
        info['accessToken'] = accountData[5];
        info['clientToken'] = accountData[6];
        break;
    }
    return info;
  }

  // 添加账号
  Future<void> _addAccount() async {
    await Navigator.push(context, SlidePageRoute(page: const NewAccountPage()));
    if (mounted) {
      _loadAccounts();
    }
  }

  // 登录模式
  String _getLoginModeText(String loginMode) {
    switch (loginMode) {
      case '0':
        return '离线登录';
      case '1':
        return '正版登录';
      case '2':
        return '外置登录';
      default:
        return '未知类型';
    }
  }

  // 删除账号
  Future<void> _deleteAccount(String name, String type) async {
    final prefs = await SharedPreferences.getInstance();
    if (type == '0') {
      final accountList = prefs.getStringList('offline_accounts_list') ?? [];
      accountList.remove(name);
      await prefs.setStringList('offline_accounts_list', accountList);
      await prefs.remove('offline_account_$name');
      LogUtil.log('已删除离线账号: $name', level: 'INFO');
    }
    if (type == '1') {
      final accountList = prefs.getStringList('online_accounts_list') ?? [];
      accountList.remove(name);
      await prefs.setStringList('online_accounts_list', accountList);
      await prefs.remove('online_account_$name');
      LogUtil.log('已删除正版账号: $name', level: 'INFO');
    }
    if (type == '2') {
      final accountList = prefs.getStringList('external_accounts_list') ?? [];
      accountList.remove(name);
      await prefs.setStringList('external_accounts_list', accountList);
      await prefs.remove('external_account_$name');
      LogUtil.log('已删除外置登录账号: $name', level: 'INFO');
    }
    if (name == prefs.getString('SelectedAccountName')) {
      await prefs.remove('SelectedAccountName');
      await prefs.remove('SelectedAccountType');
    }
    _loadAccounts();
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已删除账号: $name')));
  }

  // 删除账号提示框
  Future<void> _showDeleteDialog(String name, String type) async {
    String typeInfo;
    if (type == '0') {
      typeInfo = '离线登录';
    } else if (type == '1') {
      typeInfo = '正版登录';
    } else if (type == '2') {
      typeInfo = '外置登录';
    } else {
      typeInfo = '未知类型';
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除账号'),
        content: Text('确定删除 $typeInfo 账号 $name ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              _deleteAccount(name, type);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // 构建账号列表组件
  Widget _buildAccountsList(List<String> accounts, String type, String title) {
    if (accounts.isEmpty) {
      return Container();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ...accounts.map(
          (name) => FutureBuilder<Map<String, dynamic>>(
            future: _getAccountInfo(name, type),
            builder: (context, snapshot) {
              if (!snapshot.hasData ||
                  snapshot.data?.containsKey('error') == true) {
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.error),
                    title: Text(name),
                    subtitle: Text(snapshot.data?['error'] ?? '加载账号信息失败'),
                  ),
                );
              }
              final data = snapshot.data!;
              final uuid = data['uuid'] ?? '';
              String subtitle = '';
              if (type == '0') {
                subtitle += _getLoginModeText(type);
                if (data['isCustomUUID'] == '1') {
                  subtitle += '\n已启用自定义UUID: ${data['customUUID']}\n';
                } else {
                  subtitle += '\nUUID: $uuid';
                }
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    title: Text(name),
                    subtitle: Text(subtitle),
                    onTap: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('SelectedAccountName', name);
                      await prefs.setString('SelectedAccountType', type);
                      if (!mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('已切换账号: $name')));
                      Navigator.pop(context);
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          SlidePageRoute(
                            page: OfflineAccountManagementPage(
                              accountName: name,
                            ),
                          ),
                        );
                        if (mounted) {
                          _loadAccounts();
                        }
                      },
                    ),
                  ),
                );
              }
              subtitle += _getLoginModeText(type);
              subtitle += '\nUUID: $uuid';
              if (type == '2') {
                subtitle += '\n用户名: ${data['username'] ?? '错误'}';
                subtitle += '\n服务器URL: ${data['serverUrl'] ?? '错误'}';
              }
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(name),
                  subtitle: Text(subtitle),
                  onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('SelectedAccountName', name);
                    await prefs.setString('SelectedAccountType', type);
                    if (!mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('已切换账号: $name')));
                    Navigator.pop(context);
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () async {
                      _showDeleteDialog(name, type);
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('账号管理')),
      body:
          (_offlineAccounts.isEmpty &&
              _onlineAccounts.isEmpty &&
              _externalAccounts.isEmpty)
          ? const Center(child: Text('暂无账号'))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAccountsList(_offlineAccounts, '0', '离线账号'),
                  _buildAccountsList(_onlineAccounts, '1', '正版账号'),
                  _buildAccountsList(_externalAccounts, '2', '外置登录账号'),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addAccount,
        child: const Icon(Icons.add),
      ),
    );
  }
}
