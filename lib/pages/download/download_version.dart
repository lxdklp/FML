import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:fml/constants.dart';
import 'package:fml/function/dio_client.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:fml/models/minecraft_version.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
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
    _versionsFuture = _fetchAndParseVersionManifest();
  }

  ///
  /// 获取版本清单并解析（BMCL API）
  ///
  Future<List<MinecraftVersion>> _fetchAndParseVersionManifest() async {
    try {
      final options = Options(responseType: ResponseType.plain);

      LogUtil.log('开始请求版本清单', level: 'INFO');

      final response = await DioClient().dio.get(
        'https://bmclapi2.bangbang93.com/mc/game/version_manifest.json',
        options: options,
      );

      if (response.statusCode == 200) {
        dynamic responseData = response.data;

        /* 
         * responseData示例
         * 
         *  {
            "latest": {...},
            "versions": [...]
            }
         */

        // 如果响应数据是字符串的话就先解析(BMCL API有时会返回JSON String)
        if (responseData is String) {
          LogUtil.log("正在尝试将JSON String解析为JSON", level: 'INFO');
          try {
            responseData = jsonDecode(responseData);
          } catch (e) {
            LogUtil.log("JSON解析失败: $responseData\nerror: $e", level: 'ERROR');
            throw FormatException('无效的JSON格式: $responseData');
          }
        }

        if (responseData is! Map) {
          LogUtil.log(
            "响应数据格式不符合预期: 期望为包含'versions'字段的JSON对象，实际为: ${responseData.runtimeType}",
            level: 'ERROR',
          );
          throw const FormatException("响应数据格式不正确: 顶层JSON应为包含'versions'字段的对象");
        }

        final dynamic versionsField = (responseData)['versions'];
        if (versionsField is! List) {
          LogUtil.log(
            "响应数据缺少'versions'字段或类型不正确: ${versionsField.runtimeType}",
            level: 'ERROR',
          );
          throw const FormatException("响应数据格式不正确: 'versions'字段缺失或不是列表类型");
        }

        final List<dynamic> rawList = versionsField;
        // 将JSON转换为Dart Model
        final List<MinecraftVersion> versions = rawList
            .map((json) => MinecraftVersion.fromJson(json))
            .toList();

        LogUtil.log('成功解析版本数据，共${versions.length}个版本', level: 'INFO');

        return versions;
      } else {
        LogUtil.log(
          '拉取版本时出错: ${response.statusMessage}, 状态码: ${response.statusCode}',
        );

        throw Exception('错误: ${response.statusMessage}');
      }
    } catch (e) {
      LogUtil.log('拉取版本时出错, $e');
      rethrow;
    }
  }

  // 打开URL
  Future<void> _launchURL(String url) async {
    try {
      final Uri uri = Uri.parse(url);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法打开链接: $url')));
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发生错误: $e')));
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
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, fill: 1, size: 48),
                  const SizedBox(height: kDefaultPadding),
                  Text('Loading failed'),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: kDefaultPadding / 2,
                      horizontal: kDefaultPadding * 2,
                    ),
                    child: Text(
                      snapshot.error?.toString() ?? '数据为空',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),

                  // 重试按钮
                  ElevatedButton(
                    onPressed: () {
                      if (!mounted) return;
                      setState(() {
                        LogUtil.log('正在尝试重新拉取版本');
                        _versionsFuture = _fetchAndParseVersionManifest();
                      });
                    },
                    child: const Text('重试'),
                  ),
                ],
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
                  // 粘滞行SegmentedButton
                  SliverAppBar(
                    pinned: true,
                    floating: false,
                    snap: false,

                    title: SizedBox(
                      // 使SegmentedButton占满宽度并居中
                      width: double.infinity,

                      // 避免缩小时溢出，用Shift+滚轮可滚动
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

            // 显示CircularProgressIndicator打底
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
