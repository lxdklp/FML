import 'package:flutter/material.dart' hide LicensePage;
import 'package:fml/constants.dart';
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法打开链接: $url')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发生错误: $e')));
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
      appBar: AppBar(title: const Text('关于')),
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
                            'assets/img/icon/logo_transparent.png',
                            height: 150,
                          ),
                        ),
                        const SizedBox(width: 70),
                        Flexible(
                          child: Image.asset(
                            'assets/img/logo/flutter.png',
                            height: 150,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '$kAppName Version $_appVersion',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      'Copyright © 2025 lxdklp. All rights reserved\n',
                      style: TextStyle(
                        fontSize: 15,
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
              subtitle: const Text(AppUrls.officialWebsite),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _launchURL(AppUrls.officialWebsite),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              title: const Text('GitHub'),
              subtitle: const Text(AppUrls.githubProject),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _launchURL(AppUrls.githubProject),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              title: const Text('BUG反馈与建议'),
              subtitle: const Text('${AppUrls.githubProject}/issues'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _launchURL('${AppUrls.githubProject}/issues'),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              title: Text('许可'),
              subtitle: Text('感谢各位依赖库的贡献者'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => showLicensePage(context: context),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                const ListTile(title: Text('鸣谢'), subtitle: Text('排名不分先后顺序')),
                ListTile(
                  title: const Text('bangbang93'),
                  subtitle: const Text(
                    '下载源 BMCLAPI 维护者\nhttps://bmclapidoc.bangbang93.com',
                  ),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://bmclapidoc.bangbang93.com'),
                ),
                ListTile(
                  title: const Text('gh-proxy.com'),
                  subtitle: const Text('GitHub 加速下载\nhttps://gh-proxy.com'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://gh-proxy.com'),
                ),
                ListTile(
                  title: const Text('Modrinth'),
                  subtitle: const Text('资源下载\nhttps://modrinth.com'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://modrinth.com'),
                ),
                ListTile(
                  title: const Text('CurseForge'),
                  subtitle: const Text('资源下载\nhttps://www.curseforge.com'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://www.curseforge.com'),
                ),
                ListTile(
                  title: const Text('Sawaratsuki'),
                  subtitle: const Text(
                    'Flutter LOGO 绘制\nhttps://github.com/SAWARATSUKI/KawaiiLogos',
                  ),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () =>
                      _launchURL('https://github.com/SAWARATSUKI/KawaiiLogos'),
                ),
                ListTile(
                  title: const Text('Noto CJK fonts'),
                  subtitle: const Text(
                    '软件字体\nhttps://github.com/notofonts/noto-cjk',
                  ),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () =>
                      _launchURL('https://github.com/notofonts/noto-cjk'),
                ),
                ListTile(
                  title: const Text('GNU General Public License Version 3'),
                  subtitle: const Text(
                    '开源协议\nhttps://www.gnu.org/licenses/gpl-3.0.html',
                  ),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () =>
                      _launchURL('https://www.gnu.org/licenses/gpl-3.0.html'),
                ),
                ListTile(
                  title: const Text('authlib-injector'),
                  subtitle: const Text(
                    '外置登录\nhttps://github.com/yushijinhun/authlib-injector',
                  ),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL(
                    'https://github.com/yushijinhun/authlib-injector',
                  ),
                ),
                ListTile(
                  title: const Text('EasyTier'),
                  subtitle: const Text('异地组网\nhttps://easytier.cn/'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://easytier.cn/'),
                ),
                ListTile(
                  title: const Text('Scaffolding-MC'),
                  subtitle: const Text(
                    '联机协议\nhttps://github.com/Scaffolding-MC/Scaffolding-MC',
                  ),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL(
                    'https://github.com/Scaffolding-MC/Scaffolding-MC',
                  ),
                ),
                ListTile(
                  title: const Text('Terracotta'),
                  subtitle: const Text(
                    '联机实现参考\nhttps://github.com/burningtnt/Terracotta',
                  ),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () =>
                      _launchURL('https://github.com/burningtnt/Terracotta'),
                ),
                ListTile(
                  title: const Text('HMCL'),
                  subtitle: const Text(
                    '部分功能实现参考\nhttps://github.com/HMCL-dev/HMCL',
                  ),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/HMCL-dev/HMCL'),
                ),
                ListTile(
                  title: const Text('futurw4v'),
                  subtitle: const Text('贡献者\nhttps://github.com/futurw4v'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/futurw4v'),
                ),
                const ListTile(
                  title: Text('GitHub 上提出 Issue 等的各位'),
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
