import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:fml/function/dio_client.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fml/function/log.dart';
import 'package:fml/pages/download/curseforge/info.dart';

class DownloadCurseforge extends StatefulWidget {
  const DownloadCurseforge({super.key});

  @override
  DownloadCurseforgeState createState() => DownloadCurseforgeState();
}

class DownloadCurseforgeState extends State<DownloadCurseforge> {
  List<dynamic> _projectsList = [];
  bool _isLoading = true;
  String? _error;
  String _apiKey = '';
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToTop = false;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  int? _selectedClassId;
  bool _isSearching = false;
  bool _apiKeyConfigured = false;

  // Minecraft 游戏ID
  static const int minecraftGameId = 432;

  // 项目类型映射 (classId)
  final Map<int, String> classIdNames = {
    6: '模组',
    4471: '整合包',
    12: '资源包',
    6552: '光影',
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _scrollController.addListener(() {
      setState(() {
        _showScrollToTop = _scrollController.offset > 200;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _apiKeyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // 滚动到顶部
  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  // 读取设置
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('curseforge_api_key') ?? '';
    setState(() {
      _apiKey = apiKey;
      _apiKeyController.text = apiKey;
      _apiKeyConfigured = apiKey.isNotEmpty;
    });
    if (_apiKeyConfigured) {
      _fetchFeaturedProjects();
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 获取请求选项
  Options _getRequestOptions() {
    return Options(headers: {'x-api-key': _apiKey});
  }

  // 获取精选/热门项目
  Future<void> _fetchFeaturedProjects() async {
    if (!_apiKeyConfigured) return;
    try {
      setState(() {
        _isLoading = true;
        _error = null;
        _isSearching = false;
      });
      LogUtil.log('开始请求CurseForge热门项目', level: 'INFO');
      final response = await DioClient().dio.post(
        'https://api.curseforge.com/v1/mods/featured',
        data: {'gameId': minecraftGameId, 'excludedModIds': []},
        options: _getRequestOptions(),
      );
      if (response.statusCode == 200) {
        LogUtil.log('成功获取CurseForge项目', level: 'INFO');
        final data = response.data['data'];
        List<dynamic> allProjects = [];
        if (data['featured'] != null) {
          allProjects.addAll(data['featured']);
        }
        if (data['popular'] != null) {
          allProjects.addAll(data['popular']);
        }
        if (data['recentlyUpdated'] != null) {
          allProjects.addAll(data['recentlyUpdated']);
        }
        // 去重
        final seen = <int>{};
        allProjects = allProjects.where((project) {
          final id = project['id'] as int;
          if (seen.contains(id)) return false;
          seen.add(id);
          return true;
        }).toList();
        setState(() {
          _projectsList = allProjects;
          _isLoading = false;
        });
      } else {
        LogUtil.log('请求失败：状态码 ${response.statusCode}', level: 'ERROR');
        setState(() {
          _error = '请求失败：服务器返回状态码 ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      LogUtil.log('请求出错: $e', level: 'ERROR');
      if (mounted) {
        setState(() {
          _error = '网络请求失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  // 搜索
  Future<void> _searchProjects(String query) async {
    if (!_apiKeyConfigured) return;
    if (query.isEmpty && _selectedClassId == null) {
      _fetchFeaturedProjects();
      return;
    }
    try {
      setState(() {
        _isLoading = true;
        _error = null;
        _isSearching = true;
      });
      final Map<String, dynamic> queryParams = {
        'gameId': minecraftGameId,
        'pageSize': 50,
      };
      if (query.isNotEmpty) {
        queryParams['searchFilter'] = query;
      }
      if (_selectedClassId != null) {
        queryParams['classId'] = _selectedClassId;
      }
      LogUtil.log(
        '搜索CurseForge项目: $query, 类型: $_selectedClassId',
        level: 'INFO',
      );
      final response = await DioClient().dio.get(
        'https://api.curseforge.com/v1/mods/search',
        queryParameters: queryParams,
        options: _getRequestOptions(),
      );
      if (response.statusCode == 200) {
        LogUtil.log('成功获取搜索结果', level: 'INFO');
        setState(() {
          _projectsList = response.data['data'] ?? [];
          _isLoading = false;
        });
      } else {
        LogUtil.log('搜索失败：状态码 ${response.statusCode}', level: 'ERROR');
        setState(() {
          _error = '搜索失败：服务器返回状态码 ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      LogUtil.log('搜索出错: $e', level: 'ERROR');
      if (mounted) {
        setState(() {
          _error = '搜索失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  // 清除搜索
  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _selectedClassId = null;
      _isSearching = false;
    });
    _fetchFeaturedProjects();
  }

  // 获取项目类型名称
  String _getClassTypeName(int? classId) {
    if (classId == null) return '未知';
    return classIdNames[classId] ?? '其他';
  }

  // 类型标签
  Widget _buildTypeChip(int? classId) {
    if (classId == null) {
      return const SizedBox.shrink();
    }
    final typeName = _getClassTypeName(classId);
    return Chip(
      label: Text(typeName),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelStyle: const TextStyle(fontSize: 10),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  // 搜索框
  Widget _buildSearchBar() {
    return Card(
      margin: const EdgeInsets.all(8.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '在CurseForge搜索',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearch,
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 12.0,
                  horizontal: 16.0,
                ),
              ),
              onSubmitted: (value) => _searchProjects(value),
              textInputAction: TextInputAction.search,
            ),
            const SizedBox(height: 12.0),
            const Text(
              '项目类型',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4.0),
            DropdownButton<int>(
              isExpanded: true,
              hint: const Text('选择项目类型'),
              value: _selectedClassId,
              underline: Container(height: 1),
              items: [
                const DropdownMenuItem<int>(value: null, child: Text('全部类型')),
                ...classIdNames.entries.map(
                  (entry) => DropdownMenuItem<int>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                ),
              ],
              onChanged: (int? newValue) {
                setState(() {
                  _selectedClassId = newValue;
                });
                _searchProjects(_searchController.text);
              },
            ),
          ],
        ),
      ),
    );
  }

  // 项目卡片
  Widget _buildProjectCard(dynamic project) {
    final logo = project['logo'];
    final logoUrl = logo != null ? logo['thumbnailUrl'] : null;
    final categories = project['categories'] as List<dynamic>? ?? [];
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: ListTile(
        leading: logoUrl != null
            ? Image.network(
                logoUrl,
                width: 50,
                height: 50,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.extension, size: 50),
              )
            : const Icon(Icons.extension, size: 50),
        title: Row(
          children: [
            if (project['classId'] != null)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: _buildTypeChip(project['classId']),
              ),
            Expanded(
              child: Text(
                project['name'] ?? 'Unknown Title',
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              project['summary'] ?? 'No description available',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            if (categories.isNotEmpty)
              Wrap(
                spacing: 4,
                children: categories
                    .take(3)
                    .map<Widget>(
                      (category) => Chip(
                        label: Text(category['name'] ?? ''),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        labelStyle: const TextStyle(fontSize: 10),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.download, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${_formatDownloadCount(project['downloadCount'] ?? 0)} 次下载',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        onTap: () => Navigator.push(
          context,
          SlidePageRoute(
            page: CurseforgeInfoPage(
              modId: project['id'],
              projectInfo: project,
              apiKey: _apiKey,
            ),
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _isSearching
                  ? _searchProjects(_searchController.text)
                  : _fetchFeaturedProjects(),
              child: const Text('重试'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                setState(() {
                  _apiKeyConfigured = false;
                });
              },
              child: const Text('重新配置API Key'),
            ),
          ],
        ),
      );
    } else if (_projectsList.isEmpty) {
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('未找到相关项目'),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _clearSearch, child: const Text('清除搜索')),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => _isSearching
            ? _searchProjects(_searchController.text)
            : _fetchFeaturedProjects(),
        child: ListView.builder(
          controller: _scrollController,
          itemCount: _projectsList.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildSearchBar();
            }
            final project = _projectsList[index - 1];
            return _buildProjectCard(project);
          },
        ),
      );
    }
    return Scaffold(
      body: body,
      floatingActionButton: _apiKeyConfigured
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_showScrollToTop)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10.0),
                    child: FloatingActionButton(
                      heroTag: 'cfScrollToTopButton',
                      onPressed: _scrollToTop,
                      child: const Icon(Icons.arrow_upward),
                    ),
                  ),
                FloatingActionButton(
                  heroTag: 'cfRefreshButton',
                  onPressed: _clearSearch,
                  child: const Icon(Icons.refresh),
                ),
              ],
            )
          : null,
    );
  }
}
