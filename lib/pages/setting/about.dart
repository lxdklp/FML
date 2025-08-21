import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  AboutPageState createState() => AboutPageState();
}

class AboutPageState extends State<AboutPage> {

  String _appVersion = "unknown";

  Future<void> _loadAppVersion() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _appVersion = prefs.getString('version') ?? "unknown";
    });
  }

  // 打开URL
  Future<void> _launchURL(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开链接: $url')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发生错误: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('关于'),
      ),
      body: ListView(
        children: [
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      '\n本项目使用GPL3.0协议开源,使用过程中请遵守GPL3.0协议\n',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Image.asset(
                            'assets/img/icon/icon.png',
                            height: 150,
                          ),
                        ),
                        const SizedBox(width: 70), // 两张图片之间的间距
                        Flexible(
                          child: Image.asset(
                            'assets/img/logo/flutter.png',
                            height: 150,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16), // 图片和文字之间的间距
                    Text(
                      'Flutter Minecraft Launcher Version $_appVersion',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      'Code by lxdklp\n',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              title: const Text('官网'),
              subtitle: const Text('https://fml.lxdklp.top'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _launchURL('https://fml.lxdklp.top'),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              title: const Text('Github'),
              subtitle: const Text('https://github.com/lxdklp/FML'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _launchURL('https://github.com/lxdklp/FML'),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                const ListTile(
                  title: Text('鸣谢'),
                  subtitle: Text('没有你们就没有这个项目!'),
                ),
                ListTile(
                  title: const Text('bangbang93'),
                  subtitle: const Text('下载源 BMCLAPI 维护者\nhttps://bmclapidoc.bangbang93.com'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://bmclapidoc.bangbang93.com'),
                ),
                ListTile(
                  title: const Text('Sawaratsuki'),
                  subtitle: const Text('Flutter LOGO 绘制\nhttps://github.com/SAWARATSUKI/KawaiiLogos'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/SAWARATSUKI/KawaiiLogos'),
                ),
                ListTile(
                  title: const Text('Noto CJK fonts'),
                  subtitle: const Text('软件字体\nhttps://github.com/notofonts/noto-cjk'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/notofonts/noto-cjk'),
                ),
                const ListTile(
                  title: Text('本项目使用的开源库'),
                ),
                ListTile(
                  title: const Text('flutter'),
                  subtitle: const Text('https://github.com/flutter/flutter'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/flutter/flutter'),
                ),
                ListTile(
                  title: const Text('cupertino_icons'),
                  subtitle: const Text('https://github.com/flutter/packages/tree/main/third_party/packages/cupertino_icons'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/flutter/packages/tree/main/third_party/packages/cupertino_icons'),
                ),
                ListTile(
                  title: const Text('path'),
                  subtitle: const Text('https://github.com/dart-lang/core/tree/main/pkgs/path'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/dart-lang/core/tree/main/pkgs/path'),
                ),
                ListTile(
                  title: const Text('shared_preferences'),
                  subtitle: const Text('https://github.com/flutter/packages/tree/main/packages/shared_preferences/shared_preferences'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/flutter/packages/tree/main/packages/shared_preferences/shared_preferences'),
                ),
                ListTile(
                  title: const Text('crypto'),
                  subtitle: const Text('https://github.com/dart-lang/core/tree/main/pkgs/crypto'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/dart-lang/core/tree/main/pkgs/crypto'),
                ),
                ListTile(
                  title: const Text('file_selector'),
                  subtitle: const Text('https://github.com/flutter/packages/tree/main/packages/file_selector/file_selector'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/flutter/packages/tree/main/packages/file_selector/file_selector'),
                ),
                ListTile(
                  title: const Text('system_info2'),
                  subtitle: const Text('https://github.com/onepub-dev/system_info'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/onepub-dev/system_info'),
                ),
                ListTile(
                  title: const Text('file_picker'),
                  subtitle: const Text('https://github.com/miguelpruivo/flutter_file_picker'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/miguelpruivo/flutter_file_picker'),
                ),
                ListTile(
                  title: const Text('flutter_launcher_icons'),
                  subtitle: const Text('https://github.com/fluttercommunity/flutter_launcher_icons'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/fluttercommunity/flutter_launcher_icons'),
                ),
                ListTile(
                  title: const Text('dio'),
                  subtitle: const Text('https://github.com/cfug/dio/tree/main/dio'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/cfug/dio/tree/main/dio'),
                ),
                ListTile(
                  title: const Text('path_provider'),
                  subtitle: const Text('https://pub.dev/packages/path_provider'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://pub.dev/packages/path_provider'),
                ),
                ListTile(
                  title: const Text('url_launcher'),
                  subtitle: const Text('https://github.com/flutter/packages/tree/main/packages/url_launcher/url_launcher'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/flutter/packages/tree/main/packages/url_launcher/url_launcher'),
                ),ListTile(
                  title: const Text('archive'),
                  subtitle: const Text('https://github.com/brendan-duncan/archive'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/flutter/packages/tree/main/packages/url_launcher/url_launcher'),
                ),ListTile(
                  title: const Text('flutter_colorpicker'),
                  subtitle: const Text('https://github.com/mchome/flutter_colorpicker'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/mchome/flutter_colorpicker'),
                ),ListTile(
                  title: const Text('flutter_local_notifications'),
                  subtitle: const Text('https://github.com/MaikuB/flutter_local_notifications/tree/master/flutter_local_notifications'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/MaikuB/flutter_local_notifications/tree/master/flutter_local_notifications'),
                ),ListTile(
                  title: const Text('synchronized'),
                  subtitle: const Text('https://github.com/tekartik/synchronized.dart/tree/master/synchronized'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/tekartik/synchronized.dart/tree/master/synchronized'),
                ),
                const ListTile(
                  title: Text('Github的各位'),
                  subtitle: Text('谢谢大家'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}