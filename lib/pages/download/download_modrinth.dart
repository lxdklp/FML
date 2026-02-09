import 'package:flutter/material.dart';
import 'package:fml/function/dio_client.dart';
import 'package:fml/function/slide_page_route.dart';

import 'package:fml/function/log.dart';
import 'package:fml/pages/download/modrinth/info.dart';

class DownloadModrinth extends StatefulWidget {
  const DownloadModrinth({super.key});

  @override
  DownloadModrinthState createState() => DownloadModrinthState();
}

class DownloadModrinthState extends State<DownloadModrinth> {
  List<dynamic> _projectsList = [];
  bool _isLoading = true;
  String? _error;
  String _count = '50';
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToTop = false;
  final TextEditingController _searchController = TextEditingController();
  String? _selectedProjectType;
  bool _isSearching = false;

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
    _fetchProjects();
    _scrollController.addListener(() {
      setState(() {
        _showScrollToTop = _scrollController.offset > 200;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
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

  // 获取随机项目
  Future<void> _fetchProjects() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      LogUtil.log('开始请求Modrinth随机项目', level: 'INFO');
      final response = await DioClient().dio.get(
        'https://api.modrinth.com/v2/projects_random?count=$_count',
      );
      if (response.statusCode == 200) {
        LogUtil.log('成功获取Modrinth项目', level: 'INFO');
        setState(() {
          _projectsList = response.data;
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
    if (query.isEmpty && _selectedProjectType == null) {
      _fetchProjects();
      return;
    }
    try {
      setState(() {
        _isLoading = true;
        _error = null;
        _isSearching = true;
      });
      final Map<String, dynamic> queryParams = {'query': query};
      if (_selectedProjectType != null) {
        queryParams['facets'] = '[["project_type:$_selectedProjectType"]]';
      }
      LogUtil.log(
        '搜索Modrinth项目: $query, 类型: $_selectedProjectType',
        level: 'INFO',
      );
      final response = await DioClient().dio.get(
        'https://api.modrinth.com/v2/search',
        queryParameters: queryParams,
      );
      if (response.statusCode == 200) {
        LogUtil.log('成功获取搜索结果', level: 'INFO');
        setState(() {
          _projectsList = response.data['hits'] ?? [];
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
      _selectedProjectType = null;
      _isSearching = false;
    });
    _fetchProjects();
  }

  // 类型标签
  Widget _buildTypeChip(String? type) {
    if (type == null || !projectTypeNames.containsKey(type)) {
      return const SizedBox.shrink();
    }
    return Chip(
      label: Text(projectTypeNames[type]!),
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
                hintText: '在Modrinth搜索',
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
            DropdownButton<String>(
              isExpanded: true,
              hint: const Text('选择项目类型'),
              value: _selectedProjectType,
              underline: Container(height: 1),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('全部类型'),
                ),
                ...projectTypeNames.entries.map(
                  (entry) => DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                ),
              ],
              onChanged: (String? newValue) {
                setState(() {
                  _selectedProjectType = newValue;
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
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: ListTile(
        leading: project['icon_url'] != null
            ? Image.network(
                project['icon_url'],
                width: 50,
                height: 50,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.extension, size: 50),
              )
            : const Icon(Icons.extension, size: 50),
        title: Row(
          children: [
            if (project['project_type'] != null)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: _buildTypeChip(project['project_type']),
              ),
            Expanded(
              child: Text(
                project['title'] ?? 'Unknown Title',
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
              project['description'] ?? 'No description available',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                ...?project['categories']?.map<Widget>(
                  (category) => Chip(
                    label: Text(category),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelStyle: const TextStyle(fontSize: 10),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        onTap: () => Navigator.push(
          context,
          SlidePageRoute(
            page: InfoPage(slug: project['slug'] ?? '', projectInfo: project),
          ),
        ),
      ),
    );
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
                  : _fetchProjects(),
              child: const Text('重试'),
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
            : _fetchProjects(),
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showScrollToTop)
            Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: FloatingActionButton(
                heroTag: 'scrollToTopButton',
                onPressed: _scrollToTop,
                child: const Icon(Icons.arrow_upward),
              ),
            ),
          FloatingActionButton(
            heroTag: 'refreshButton',
            onPressed: _clearSearch,
            child: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}
