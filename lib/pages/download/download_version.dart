import 'package:material_ui/material_ui.dart';
import 'package:fml/constants.dart';
import 'package:fml/function/minecraft_manifest.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:fml/models/minecraft_version.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fml/pages/download/download_version/download_game.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fml/function/log.dart';

class DownloadVersionPage extends StatefulWidget {
  const DownloadVersionPage({super.key});

  @override
  DownloadVersionPageState createState() => DownloadVersionPageState();
}

class DownloadVersionPageState extends State<DownloadVersionPage> {
  ///
  /// 当前选择的版本，默认为正式版
  ///
  Set<VersionType> _versionTypeSelection = <VersionType>{VersionType.release};

  late Future<List<MinecraftVersion>> _versionsFuture;
  static final DateFormat dateFormat = DateFormat("yyyy-MM-dd HH:mm:ss");

  // 顶部ButtonSegments
  static final segments = <ButtonSegment<VersionType>>[
    ButtonSegment<VersionType>(
      value: VersionType.release,
      label: Text(VersionType.release.getVersionTypeLabel()),
    ),
    ButtonSegment<VersionType>(
      value: VersionType.snapshot,
      label: Text(VersionType.snapshot.getVersionTypeLabel()),
    ),
    ButtonSegment<VersionType>(
      value: VersionType.oldBeta,
      label: Text(VersionType.oldBeta.getVersionTypeLabel()),
    ),
    ButtonSegment<VersionType>(
      value: VersionType.oldAlpha,
      label: Text(VersionType.oldAlpha.getVersionTypeLabel()),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _versionsFuture = fetchMinecraftManifest();
  }

  // 打开URL
  Future<void> _launchURL(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开链接: $url')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('发生错误: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FutureBuilder(
          future: _versionsFuture,
          builder: (context, snapshot) {
            // 加载时显示CircularProgressIndicator
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const CircularProgressIndicator();
            }
            // 错误处理
            if (snapshot.hasError || snapshot.data == null) {
              // 返回错误信息和重试按钮
              return LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(kDefaultPadding),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, fill: 1, size: 48),
                            const SizedBox(height: kDefaultPadding),
                            const Text('版本列表加载失败'),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: kDefaultPadding / 2,
                              ),
                              child: Text(
                                snapshot.error?.toString() ?? '没有可用的版本数据，请重试。',
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () => setState(() {
                                _versionsFuture = fetchMinecraftManifest();
                              }),
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            }
            // 数据加载成功，显示版本列表
            if (snapshot.connectionState == ConnectionState.done) {
              // 强制转为Notnull
              final List<MinecraftVersion> versions = snapshot.data!;
              // 筛选当前选择的版本类型
              final filteredVersions = versions
                  .where(
                    (version) => version.type == _versionTypeSelection.first,
                  )
                  .toList();
              return CustomScrollView(
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    floating: false,
                    snap: false,
                    title: SizedBox(
                      width: double.infinity,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<VersionType>(
                          segments: segments,
                          selected: _versionTypeSelection,
                          onSelectionChanged: (Set<VersionType> newSelection) {
                            setState(() {
                              _versionTypeSelection = newSelection;
                            });
                          },
                        ),
                      ),
                    ),
                    elevation: 4,
                  ),
                  // BMCL广告
                  SliverToBoxAdapter(
                    child: _buildTappableCard(
                      child: ListTile(
                        title: const Text('下载由 BMCLAPI 提供'),
                        subtitle: const Text('赞助 BMCLAPI 喵~ 赞助 BMCLAPI 谢谢喵~ '),
                        leading: const Icon(Icons.info),
                        trailing: const Icon(Icons.open_in_new),
                      ),
                      onTap: () =>
                          _launchURL('https://bmclapi2.bangbang93.com/'),
                    ),
                  ),
                  // 版本列表
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final version = filteredVersions[index];
                      return _buildTappableCard(
                        child: ListTile(
                          title: Text(
                            version.id,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          subtitle: Text(
                            '更新时间: ${dateFormat.format(DateTime.parse(version.releaseTime).toLocal())}',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                        onTap: () async {
                          // 读取选择路径
                          final prefs = await SharedPreferences.getInstance();
                          final selectedDir = prefs.getString('SelectedPath');
                          if (!mounted) return;
                          // 检查下载路径是否存在
                          if (selectedDir == null || selectedDir.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('请先选择下载目录')),
                            );
                          } else {
                            LogUtil.log(
                              '选择了版本: ${version.id} - URL: ${version.url}',
                              level: 'INFO',
                            );
                            Navigator.push(
                              context,
                              SlidePageRoute(
                                page: DownloadGamePage(version: version),
                              ),
                            );
                          }
                        },
                      );
                    }, childCount: filteredVersions.length),
                  ),
                ],
              );
            }
            return const CircularProgressIndicator();
          },
        ),
      ),
    );
  }

  ///
  /// 构建一个带有InkWell的Card
  ///
  /// 带有默认的内边距，圆角，点击时触发[onTap]回调
  ///
  Card _buildTappableCard({
    required Widget child,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(
        vertical: kDefaultPadding / 2,
        horizontal: kDefaultPadding / 2,
      ),
      child: InkWell(
        onTap: onTap,
        // 圆角
        borderRadius: BorderRadius.circular(12.0),
        child: child,
      ),
    );
  }
}
