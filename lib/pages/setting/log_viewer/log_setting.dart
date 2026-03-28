import 'package:flutter/material.dart';
import 'package:fml/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LogSettingPage extends StatefulWidget {
  const LogSettingPage({super.key});

  @override
  LogSettingPageState createState() => LogSettingPageState();
}

class LogSettingPageState extends State<LogSettingPage> {
  int _logLevel = 0;
  bool _autoClearLog = false;

  // 读取日志配置信息
  Future<void> _readLogConfig() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int logLevel = prefs.getInt('logLevel') ?? 0;
    final bool autoClearLog = prefs.getBool('autoClearLog') ?? true;

    setState(() {
      _logLevel = logLevel;
      _autoClearLog = autoClearLog;
    });
  }

  // 保存日志等级配置
  Future<void> _saveLogLevel() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('logLevel', _logLevel);
  }

  // 保存日志自动清理配置
  Future<void> _saveAutoClearLog() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoClearLog', _autoClearLog);
  }

  @override
  void initState() {
    super.initState();
    _readLogConfig();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('日志设置')),
      body: Padding(
        padding: const EdgeInsets.all(kDefaultPadding),
        child: Column(
          children: [
            Card(
              clipBehavior: Clip.antiAlias,

              elevation: 0,

              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(12),
              ),

              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: kDefaultPadding,
                  vertical: kDefaultPadding / 2,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('日志等级', style: Theme.of(context).textTheme.bodyLarge),

                    const Spacer(),

                    DropdownButton<int>(
                      hint: const Text('日志等级'),
                      value: _logLevel,
                      underline: SizedBox.shrink(),
                      items: [
                        DropdownMenuItem(value: 0, child: const Text('INFO')),

                        DropdownMenuItem(
                          value: 1,
                          child: const Text('WARNING'),
                        ),

                        DropdownMenuItem(value: 2, child: const Text('ERROR')),
                      ],

                      onChanged: (int? value) {
                        setState(() {
                          _logLevel = value!;
                        });

                        _saveLogLevel();
                      },
                    ),
                  ],
                ),
              ),
            ),

            Card(
              clipBehavior: Clip.antiAlias,

              elevation: 0,

              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(12),
              ),

              child: SwitchListTile(
                title: const Text('打开 APP 时自动清理日志'),
                subtitle: const Text('当遇到 APP 崩溃时,请关闭此选项尝试抓取日志'),
                value: _autoClearLog,
                onChanged: (bool value) {
                  setState(() {
                    _autoClearLog = value;
                  });
                  _saveAutoClearLog();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
