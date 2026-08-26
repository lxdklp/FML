import 'package:material_ui/material_ui.dart' hide LicensePage;
import 'package:fml/constants.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  AboutPageState createState() => AboutPageState();
}

class AboutPageState extends State<AboutPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
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

            margin: const EdgeInsets.symmetric(horizontal: kDefaultPadding),

            child: Column(
              children: [
                Text(
                  '\n本项目使用GPL3.0协议开源,使用过程中请遵守GPL3.0协议\n',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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

                const SizedBox(height: kDefaultPadding),

                Text(
                  '$kAppName Version $gAppVersion',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),

                Text(
                  'Copyright © 2026 lxdklp. All rights reserved\n',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          _buildCardWithListTile(
            title: '官网',
            subtitle: AppUrls.officialWebsite,
            onTap: () => _launchURL(AppUrls.officialWebsite),
          ),

          _buildCardWithListTile(
            title: 'GitHub',
            subtitle: AppUrls.githubProject,
            onTap: () => _launchURL(AppUrls.githubProject),
          ),

          _buildCardWithListTile(
            title: 'BUG反馈与建议',
            subtitle: '${AppUrls.githubProject}/issues',
            onTap: () => _launchURL('${AppUrls.githubProject}/issues'),
          ),

          _buildCardWithListTile(
            title: '许可',
            subtitle: '感谢各位依赖库的贡献者',
            onTap: () => showLicensePage(context: context),
          ),

          Card(
            margin: const EdgeInsets.only(
              left: kDefaultPadding,
              right: kDefaultPadding,
              bottom: kDefaultPadding,
            ),

            clipBehavior: Clip.antiAlias,

            elevation: 0,

            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(12),
            ),

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
                  title: const Text('MCIM'),
                  subtitle: const Text(
                    '资源简介翻译\nhttps://github.com/mcmod-info-mirror',
                  ),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://github.com/mcmod-info-mirror'),
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
                ListTile(
                  title: const Text('图标画师'),
                  subtitle: const Text('https://github.com/lxdklp/FML/pull/7'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () =>
                      _launchURL('https://github.com/lxdklp/FML/pull/7'),
                ),
                ListTile(
                  title: const Text('Google 翻译'),
                  subtitle: const Text('https://translate.google.com/about'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://translate.google.com/about'),
                ),
                ListTile(
                  title: const Text('Cloudflare'),
                  subtitle: const Text('https://www.cloudflare.com'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchURL('https://www.cloudflare.com'),
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

  Card _buildCardWithListTile({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,

      elevation: 0,

      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),

      margin: const EdgeInsets.symmetric(
        horizontal: kDefaultPadding,
        vertical: kDefaultPadding / 2,
      ),

      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.open_in_new),
        onTap: onTap,
      ),
    );
  }

  ///
  /// 打开URL
  ///
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
}
