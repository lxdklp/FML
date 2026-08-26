import 'package:material_ui/material_ui.dart';
// 账号模块
import 'package:fml/function/account/offline.dart' as offline_lib;
import 'package:fml/function/account/microsoft.dart' as online_lib;
import 'package:fml/function/account/external.dart' as external_lib;

class NewAccountPage extends StatefulWidget {
  const NewAccountPage({super.key});

  @override
  NewAccountPageState createState() => NewAccountPageState();
}

class NewAccountPageState extends State<NewAccountPage> {
  // 登录模式
  String _loginMode = 'offline';
  static const String defaultAuthServer = 'https://littleskin.cn/api/yggdrasil';
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _serverUrlController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  int _onlineStatus = 0;
  List<String> token = ['',''];

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(() {
      if (_loginMode == 'authlibInjector') {
        _nameController.text = _usernameController.text;
      }
    });
  }

  @override
  void dispose() {
    // 释放控制器资源
    _nameController.dispose();
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 正版登录状态回调
  Future<void> onlineCallback(status) async {
    setState(() {
      _onlineStatus = status;
    });
  }

  // 密码可见性
  Future<void> _togglePasswordVisibility() async {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }

  // http不安全提示框
  Future<void> _showHttpWarningDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('不安全的连接'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('您正在使用不安全的HTTP协议,这可能会导致您的账号信息被窃取'),
                Text('建议您使用HTTPS协议以确保账号安全'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('无视风险继续访问'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加账号'),
      ),
      body: Center(
        child: ListView(
          children: [
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('登录模式', style: TextStyle(fontSize: 16)),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: DropdownButton<String>(
                          value: _loginMode,
                          onChanged: (String? value) {
                            setState(() {
                              _loginMode = value!;
                            });
                          },
                          items: const [
                            DropdownMenuItem(
                              value: 'offline',
                              child: Text('离线登录'),
                            ),
                            DropdownMenuItem(
                              value: 'online',
                              child: Text('正版登录'),
                            ),
                            DropdownMenuItem(
                              value: 'authlibInjector' ,
                              child: Text('外置登录(authlib-injector)'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_loginMode == 'online')
              if (_onlineStatus == 0)
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: const ListTile(
                    leading: Icon(Icons.account_circle),
                    title: Text('请点击右下角使用微软账号登录'),
                  ),
                ),
              if (_onlineStatus == 1)
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: const
                  Padding(
                      padding: EdgeInsets.all(16.0),
                      child: ListTile(
                      leading: CircularProgressIndicator(),
                      title: Text('请将启动器稍后弹出的验证代码粘贴到稍后自动打开的网页中'),
                    )
                  ),
                ),
              if (_onlineStatus == 2)
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: const
                  Padding(
                      padding: EdgeInsets.all(16.0),
                      child: ListTile(
                      leading: CircularProgressIndicator(),
                      title: Text('正在检查游戏所有权'),
                    )
                  ),
                ),
                if (_onlineStatus == 3)
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: const
                  Padding(
                      padding: EdgeInsets.all(16.0),
                      child: ListTile(
                      leading: Icon(Icons.done),
                      title: Text('完成登录'),
                    )
                  ),
                ),
                if (_onlineStatus == 4)
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: const
                  Padding(
                      padding: EdgeInsets.all(16.0),
                      child: ListTile(
                      leading: Icon(Icons.close),
                      title: Text('未购买'),
                      subtitle: Text('如果确定已购买,请尝试去 minecraft.net 查看玩家档案'),
                    )
                  ),
                ),
            if (_loginMode == 'offline')
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '离线ID \n',
                    prefixIcon: Icon(Icons.account_circle),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            if (_loginMode == 'authlibInjector')
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _serverUrlController,
                        decoration: const InputDecoration(
                          labelText: '验证服务器(留空使用littleskin)',
                          hintText: defaultAuthServer,
                          prefixIcon: Icon(Icons.dns),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: '账号',
                          prefixIcon: Icon(Icons.person),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: '密码',
                          prefixIcon: Icon(Icons.lock),
                          border: OutlineInputBorder(),
                          suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: _togglePasswordVisibility,
                        ),
                        ),
                        obscureText: _obscurePassword,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: _loginMode == 'online'
        ? _onlineStatus == 0
          ? FloatingActionButton(
            onPressed: () async {
              await online_lib.login(context, onlineCallback);
            },
            child: const Icon(Icons.login)
          )
        : _onlineStatus == 3
          ? FloatingActionButton(
            onPressed: () async {
              Navigator.of(context).pop();
            },
            child: const Icon(Icons.check),
          )
        : _onlineStatus == 4
        ? FloatingActionButton(
          onPressed: () async {
            Navigator.of(context).pop();
          },
          child: const Icon(Icons.close),
        )
        : null
      : FloatingActionButton(
        onPressed: () async {
          if (_loginMode == 'offline' && _nameController.text.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('名称不能为空')),
            );
            return;
          }
          // 处理外置登录
          if (_loginMode == 'authlibInjector') {
            // 检查用户名和密码
            if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请填写完整的账号和密码')),
              );
              return;
            }
            if (_serverUrlController.text.startsWith('http://')) {
              await _showHttpWarningDialog();
            }
            final String serverUrl = _serverUrlController.text.isEmpty ?
              defaultAuthServer : _serverUrlController.text;
            await external_lib.saveAuthLibInjectorAccount(
              context,
              serverUrl,
              _usernameController.text,
              _passwordController.text
              );
            return;
          }
          // 离线UUID生成
          if (_loginMode == 'offline') {
            offline_lib.saveOffineAccount(
              context,
              _nameController.text
              );
            return;
          }
        },
        child: const Icon(Icons.check),
      ),
    );
  }
}