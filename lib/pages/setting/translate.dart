import 'package:flutter/material.dart';
import 'package:fml/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TranslatePage extends StatefulWidget {
  const TranslatePage({super.key});

  @override
  TranslatePageState createState() => TranslatePageState();
}

class TranslatePageState extends State<TranslatePage> {
  bool _autoTranslate = true;
  bool _enableGoogleTranslate = true;
  int _googleTranslateClient = 0;

  Future<void> _readConfig() async{
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool autoTranslate = prefs.getBool('autoTranslate') ?? true;
    final bool enableGoogleTranslate = prefs.getBool('enableGoogleTranslate') ?? true;
    final int googleTranslateClient = prefs.getInt('googleTranslateClient') ?? 0;
    setState(() {
      _autoTranslate = autoTranslate;
      _enableGoogleTranslate = enableGoogleTranslate;
      _googleTranslateClient = googleTranslateClient;
    });
  }

  Future<void> _setAutoTranslate() async{
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoTranslate', _autoTranslate);
  }

  Future<void> _setEnableGoogleTranslate() async{
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('enableGoogleTranslate', _enableGoogleTranslate);
  }

  Future<void> _setGoogleTranslateClient() async{
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('googleTranslateClient', _googleTranslateClient);
  }

  @override
  void initState() {
    super.initState();
    _readConfig();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kDefaultPadding),
      child:
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: kDefaultPadding / 2,
                top: kDefaultPadding,
                bottom: kDefaultPadding,
              ),
              child: Text('翻译', style: Theme.of(context).textTheme.headlineMedium),
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
                title: const Text('自动翻译资源简介'),
                subtitle: const Text('关闭可以提高资源页加载速度,翻译内容由 mcmod-info-mirror 提供'),
                value: _autoTranslate,
                onChanged: (bool value) {
                  setState(() {
                    _autoTranslate = value;
                  });
                  _setAutoTranslate();
                },
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
                title: const Text('使用 Google 翻译进行翻译资源详细信息'),
                subtitle: const Text('Google 翻译服务使用 Cloudflare 进行代理'),
                value: _enableGoogleTranslate,
                onChanged: (bool value) {
                  setState(() {
                    _enableGoogleTranslate = value;
                  });
                  _setEnableGoogleTranslate();
                },
              ),
            ),
            if (_enableGoogleTranslate) ...[
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
                      Text('Google 翻译客户端(如不能翻译再修改)', style: Theme.of(context).textTheme.bodyLarge),
                      const Spacer(),
                      DropdownButton<int>(
                        hint: const Text('Client'),
                        value: _googleTranslateClient,
                        underline: SizedBox.shrink(),
                        items: [
                          DropdownMenuItem(value: 0, child: const Text('at (默认)')),
                          DropdownMenuItem(value: 1, child: const Text('gtx')),
                          DropdownMenuItem(value: 2, child: const Text('t')),
                          DropdownMenuItem(value: 3, child: const Text('webapp')),
                        ],
                        onChanged: (int? value) {
                          setState(() {
                            _googleTranslateClient = value!;
                          });
                          _setGoogleTranslateClient();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ]
          ],
      ),
    );
  }
}