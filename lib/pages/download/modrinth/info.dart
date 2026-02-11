import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:fml/function/dio_client.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fml/function/log.dart';
import 'package:fml/pages/download/modrinth/type/mod.dart';
import 'package:fml/pages/download/modrinth/type/modpack.dart';
import 'package:fml/pages/download/modrinth/type/resourcepack.dart';
import 'package:fml/pages/download/modrinth/type/shader.dart';

class InfoPage extends StatefulWidget {
  final String slug;
  final Map<String, dynamic> projectInfo;

  const InfoPage({super.key, required this.slug, required this.projectInfo});

  @override
  InfoPageState createState() => InfoPageState();
}

class InfoPageState extends State<InfoPage> {
  bool isLoading = true;
  Map<String, dynamic> projectDetails = {};
  String? error;

  // 项目类型映射
  final Map<String, String> projectTypeNames = {
    'mod': '模组',
    'modpack': '整合包',
    'resourcepack': '资源包',
    'shader': '光影',
  };

  @override
  void initState() {
    super.initState();
    _fetchProjectDetails();
  }

  // 获取格式化的标题
  String _getFormattedTitle() {
    final title =
        projectDetails['title'] ?? widget.projectInfo['title'] ?? '未知项目';
    final projectType = projectDetails['project_type'];
    if (projectType != null && projectTypeNames.containsKey(projectType)) {
      return '[${projectTypeNames[projectType]}] $title';
    }
    return title;
  }

  // 获取模组详情
  Future<void> _fetchProjectDetails() async {
    if (widget.slug.isEmpty) {
      setState(() {
        error = "模组ID无效";
        isLoading = false;
      });
      return;
    }
    try {
      LogUtil.log('正在获取模组详情: ${widget.slug}', level: 'INFO');
      final response = await DioClient().dio.get(
        'https://api.modrinth.com/v2/project/${widget.slug}',
      );
      if (response.statusCode == 200) {
        setState(() {
          projectDetails = response.data;
          isLoading = false;
        });
        LogUtil.log('成功获取模组详情', level: 'INFO');
      } else {
        setState(() {
          error = '请求失败: ${response.statusCode}';
          isLoading = false;
        });
        LogUtil.log('获取模组详情失败: ${response.statusCode}', level: 'ERROR');
      }
    } catch (e) {
      setState(() {
        error = '加载失败: $e';
        isLoading = false;
      });
      LogUtil.log('获取模组详情错误: $e', level: 'ERROR');
    }
  }

  // 打开链接
  Future<void> _launchURL(String? url) async {
    if (url == null || url.isEmpty) return;
    final Uri uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法打开链接: $e')));
    }
  }

  // 客户端/服务端支持信息
  Widget _buildClientServerInfo() {
    final clientSide = projectDetails['client_side'] ?? 'unknown';
    final serverSide = projectDetails['server_side'] ?? 'unknown';
    Map<String, String> statusText = {
      'required': '必需',
      'optional': '可选',
      'unsupported': '不支持',
      'unknown': '未知',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    const Text(
                      '客户端',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(statusText[clientSide] ?? clientSide),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    const Text(
                      '服务端',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(statusText[serverSide] ?? serverSide),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 支持的游戏版本
  Widget _buildGameVersions() {
    final gameVersions =
        projectDetails['game_versions'] as List<dynamic>? ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '支持的游戏版本',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: gameVersions
                  .map<Widget>(
                    (version) => Chip(
                      label: Text(version.toString()),
                      labelStyle: const TextStyle(fontSize: 12),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  // 分类和加载器
  Widget _buildCategories() {
    final categories = projectDetails['categories'] as List<dynamic>? ?? [];
    final loaders = projectDetails['loaders'] as List<dynamic>? ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('分类', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: categories
                  .map<Widget>(
                    (category) => Chip(
                      label: Text(category.toString()),
                      labelStyle: const TextStyle(fontSize: 12),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            const Text('加载器', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: loaders
                  .map<Widget>(
                    (loader) => Chip(
                      label: Text(loader.toString()),
                      labelStyle: const TextStyle(fontSize: 12),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  // 统计数据
  Widget _buildStats() {
    final downloads = projectDetails['downloads'] ?? 0;
    final followers = projectDetails['followers'] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    const Text(
                      '下载量',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(downloads.toString()),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    const Text(
                      '收藏数',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(followers.toString()),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 相关链接
  Widget _buildLinks() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('链接', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (projectDetails['source_url'] != null)
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('源代码'),
                onTap: () => _launchURL(projectDetails['source_url']),
              ),
            if (projectDetails['issues_url'] != null)
              ListTile(
                leading: const Icon(Icons.bug_report),
                title: const Text('问题反馈'),
                onTap: () => _launchURL(projectDetails['issues_url']),
              ),
            if (projectDetails['wiki_url'] != null)
              ListTile(
                leading: const Icon(Icons.menu_book),
                title: const Text('维基'),
                onTap: () => _launchURL(projectDetails['wiki_url']),
              ),
            if (projectDetails['discord_url'] != null)
              ListTile(
                leading: const Icon(Icons.discord),
                title: const Text('Discord'),
                onTap: () => _launchURL(projectDetails['discord_url']),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(error!),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _fetchProjectDetails,
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (projectDetails['icon_url'] != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              projectDetails['icon_url'],
                              width: 80,
                              height: 80,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.extension, size: 80),
                            ),
                          ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getFormattedTitle(),
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                projectDetails['description'] ?? '暂无描述',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 客户端/服务端支持信息
                    _buildClientServerInfo(),
                    // 统计数据
                    _buildStats(),
                    // 游戏版本
                    _buildGameVersions(),
                    const SizedBox(height: 16),
                    // 分类和加载器
                    _buildCategories(),
                    const SizedBox(height: 16),
                    // 相关链接
                    _buildLinks(),
                    const SizedBox(height: 16),
                    if (projectDetails['body'] != null &&
                        projectDetails['body'].toString().isNotEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '详细介绍',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Markdown(
                                data: projectDetails['body'],
                                selectable: true,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                onTapLink: (text, href, title) {
                                  if (href != null) _launchURL(href);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (projectDetails['project_type'] == 'mod') {
            Navigator.push(
              context,
              SlidePageRoute(
                page: ModPage(
                  projectId: projectDetails['id'] ?? '',
                  projectName: projectDetails['title'] ?? '',
                ),
              ),
            );
          } else if (projectDetails['project_type'] == 'modpack') {
            Navigator.push(
              context,
              SlidePageRoute(
                page: ModpackPage(
                  projectId: projectDetails['id'] ?? '',
                  projectName: projectDetails['title'] ?? '',
                ),
              ),
            );
          } else if (projectDetails['project_type'] == 'resourcepack') {
            Navigator.push(
              context,
              SlidePageRoute(
                page: ResourcepackPage(
                  projectId: projectDetails['id'] ?? '',
                  projectName: projectDetails['title'] ?? '',
                ),
              ),
            );
          } else if (projectDetails['project_type'] == 'shader') {
            Navigator.push(
              context,
              SlidePageRoute(
                page: ShaderPage(
                  projectId: projectDetails['id'] ?? '',
                  projectName: projectDetails['title'] ?? '',
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('未知的项目类型，无法下载')));
          }
        },
        child: const Icon(Icons.download),
      ),
    );
  }
}
