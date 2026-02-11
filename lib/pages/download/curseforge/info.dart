import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:fml/function/dio_client.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:share_plus/share_plus.dart';

import 'package:fml/function/log.dart';
import 'package:fml/pages/download/curseforge/type/mod.dart';
import 'package:fml/pages/download/curseforge/type/modpack.dart';
import 'package:fml/pages/download/curseforge/type/resourcepack.dart';
import 'package:fml/pages/download/curseforge/type/shader.dart';

class CurseforgeInfoPage extends StatefulWidget {
  final int modId;
  final Map<String, dynamic> projectInfo;
  final String apiKey;

  const CurseforgeInfoPage({
    super.key,
    required this.modId,
    required this.projectInfo,
    required this.apiKey,
  });

  @override
  CurseforgeInfoPageState createState() => CurseforgeInfoPageState();
}

class CurseforgeInfoPageState extends State<CurseforgeInfoPage> {
  bool isLoading = true;
  Map<String, dynamic> projectDetails = {};
  String? error;
  String _description = '';

  // 项目类型映射
  final Map<int, String> classIdNames = {
    6: '模组',
    4471: '整合包',
    12: '资源包',
    6552: '光影',
  };

  @override
  void initState() {
    super.initState();
    _fetchProjectDetails();
  }

  // 获取格式化的标题
  String _getFormattedTitle() {
    final title =
        projectDetails['name'] ?? widget.projectInfo['name'] ?? '未知项目';
    final classId = projectDetails['classId'] ?? widget.projectInfo['classId'];
    if (classId != null && classIdNames.containsKey(classId)) {
      return '[${classIdNames[classId]}] $title';
    }
    return title;
  }

  // 获取请求选项
  Options _getRequestOptions() {
    return Options(headers: {'x-api-key': widget.apiKey});
  }

  // 获取模组详情
  Future<void> _fetchProjectDetails() async {
    try {
      LogUtil.log('正在获取CurseForge项目详情: ${widget.modId}', level: 'INFO');
      final response = await DioClient().dio.get(
        'https://api.curseforge.com/v1/mods/${widget.modId}',
        options: _getRequestOptions(),
      );
      if (response.statusCode == 200) {
        setState(() {
          projectDetails = response.data['data'];
        });
        LogUtil.log('成功获取项目详情', level: 'INFO');
        await _fetchDescription();
      } else {
        setState(() {
          error = '请求失败: ${response.statusCode}';
          isLoading = false;
        });
        LogUtil.log('获取项目详情失败: ${response.statusCode}', level: 'ERROR');
      }
    } catch (e) {
      setState(() {
        error = '加载失败: $e';
        isLoading = false;
      });
      LogUtil.log('获取项目详情错误: $e', level: 'ERROR');
    }
  }

  // 获取描述
  Future<void> _fetchDescription() async {
    try {
      LogUtil.log('正在获取CurseForge项目描述: ${widget.modId}', level: 'INFO');
      final response = await DioClient().dio.get(
        'https://api.curseforge.com/v1/mods/${widget.modId}/description',
        options: _getRequestOptions(),
      );
      if (response.statusCode == 200) {
        final htmlContent = response.data['data'] ?? '';
        final document = html_parser.parse(htmlContent);
        final text = document.body?.text ?? '';
        setState(() {
          _description = text;
          isLoading = false;
        });
        LogUtil.log('成功获取项目描述', level: 'INFO');
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      LogUtil.log('获取项目描述错误: $e', level: 'ERROR');
      setState(() {
        isLoading = false;
      });
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

  // 分享项目链接
  Future<void> _shareProject(String? url) async {
    if (url == null || url.isEmpty) return;
    final Uri uri = Uri.parse(url);
    try {
      SharePlus.instance.share(
        ShareParams(uri: uri, title: '分享 CurseForge 项目'),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法分享项目: $e')));
    }
  }

  // 统计数据
  Widget _buildStats() {
    final downloads = projectDetails['downloadCount'] ?? 0;
    final thumbsUp = projectDetails['thumbsUpCount'] ?? 0;
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
                    Text(_formatDownloadCount(downloads)),
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
                      '点赞数',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(thumbsUp.toString()),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 格式化下载数
  String _formatDownloadCount(int count) {
    if (count >= 1000000000) {
      return '${(count / 1000000000).toStringAsFixed(1)}B';
    } else if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  // 支持的游戏版本
  Widget _buildGameVersions() {
    final latestFilesIndexes =
        projectDetails['latestFilesIndexes'] as List<dynamic>? ?? [];
    final gameVersions = latestFilesIndexes
        .map((file) => file['gameVersion'] as String?)
        .where((v) => v != null)
        .toSet()
        .toList();
    gameVersions.sort((a, b) => b!.compareTo(a!));
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
                  .take(20)
                  .map<Widget>(
                    (version) => Chip(
                      label: Text(version ?? ''),
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

  // 分类
  Widget _buildCategories() {
    final categories = projectDetails['categories'] as List<dynamic>? ?? [];
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
                      label: Text(category['name'] ?? ''),
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

  // 作者信息
  Widget _buildAuthors() {
    final authors = projectDetails['authors'] as List<dynamic>? ?? [];
    if (authors.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('作者', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: authors
                  .map<Widget>(
                    (author) => ActionChip(
                      label: Text(author['name'] ?? ''),
                      onPressed: () => _launchURL(author['url']),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  // 相关链接
  Widget _buildLinks() {
    final links = projectDetails['links'] as Map<String, dynamic>? ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('链接', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (links['websiteUrl'] != null &&
                links['websiteUrl'].toString().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.language),
                title: const Text('项目主页'),
                onTap: () => _launchURL(links['websiteUrl']),
              ),
            if (links['sourceUrl'] != null &&
                links['sourceUrl'].toString().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('源代码'),
                onTap: () => _launchURL(links['sourceUrl']),
              ),
            if (links['issuesUrl'] != null &&
                links['issuesUrl'].toString().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.bug_report),
                title: const Text('问题反馈'),
                onTap: () => _launchURL(links['issuesUrl']),
              ),
            if (links['wikiUrl'] != null &&
                links['wikiUrl'].toString().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.menu_book),
                title: const Text('维基'),
                onTap: () => _launchURL(links['wikiUrl']),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logo = projectDetails['logo'] ?? widget.projectInfo['logo'];
    final logoUrl = logo != null ? logo['url'] : null;
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
                        if (logoUrl != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              logoUrl,
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
                                projectDetails['summary'] ??
                                    widget.projectInfo['summary'] ??
                                    '暂无描述',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 统计数据
                    _buildStats(),
                    // 游戏版本
                    _buildGameVersions(),
                    const SizedBox(height: 16),
                    // 分类
                    _buildCategories(),
                    const SizedBox(height: 16),
                    // 作者
                    _buildAuthors(),
                    const SizedBox(height: 16),
                    // 相关链接
                    _buildLinks(),
                    const SizedBox(height: 16),
                    if (_description.isNotEmpty)
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
                              Text(
                                _description,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'share',
            onPressed: () {
              final projectUrl = projectDetails['links'] != null
                  ? projectDetails['links']['websiteUrl']
                  : null;
              _shareProject(projectUrl);
            },
            child: const Icon(Icons.share),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'download',
            onPressed: () {
              final classId =
                  projectDetails['classId'] ?? widget.projectInfo['classId'];
              if (classId == 6) {
                // 模组
                Navigator.push(
                  context,
                  SlidePageRoute(
                    page: CurseforgeModPage(
                      modId: widget.modId,
                      modName:
                          projectDetails['name'] ??
                          widget.projectInfo['name'] ??
                          '',
                      apiKey: widget.apiKey,
                    ),
                  ),
                );
              } else if (classId == 4471) {
                // 整合包
                Navigator.push(
                  context,
                  SlidePageRoute(
                    page: CurseforgeModpackPage(
                      modId: widget.modId,
                      modName:
                          projectDetails['name'] ??
                          widget.projectInfo['name'] ??
                          '',
                      apiKey: widget.apiKey,
                    ),
                  ),
                );
              } else if (classId == 12) {
                // 资源包
                Navigator.push(
                  context,
                  SlidePageRoute(
                    page: CurseforgeResourcepackPage(
                      modId: widget.modId,
                      modName:
                          projectDetails['name'] ??
                          widget.projectInfo['name'] ??
                          '',
                      apiKey: widget.apiKey,
                    ),
                  ),
                );
              } else if (classId == 6552) {
                // 光影
                Navigator.push(
                  context,
                  SlidePageRoute(
                    page: CurseforgeShaderPage(
                      modId: widget.modId,
                      modName:
                          projectDetails['name'] ??
                          widget.projectInfo['name'] ??
                          '',
                      apiKey: widget.apiKey,
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
        ],
      ),
    );
  }
}
