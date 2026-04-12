import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:fml/function/dio_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fml/function/log.dart';
import 'package:fml/pages/download/modrinth/info.dart';
import 'package:fml/pages/download/curseforge/info.dart';
import 'package:fml/constants.dart';

class DownloadResources extends StatefulWidget {
  const DownloadResources({super.key});

  @override
  DownloadResourcesState createState() => DownloadResourcesState();
}

class DownloadResourcesState extends State<DownloadResources> {
  List<dynamic> _projectsList = [];
  bool _isLoading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToTop = false;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _dataSource = 'modrinth';
  static const int minecraftGameId = 432;
  String? _modrinthProjectType;
  final Map<String, String> modrinthProjectTypes = {
    'mod': '模组',
    'modpack': '整合包',
    'resourcepack': '资源包',
    'shader': '光影',
  };

  // CurseForge项目类型 (classId)
  int? _curseforgeClassId;
  final Map<int, String> curseforgeClassIds = {
    6: '模组',
    4471: '整合包',
    12: '资源包',
    6552: '光影',
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
  Future<void> _scrollToTop() async {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  // CurseForge 请求头
  Options _getCurseforgeOptions() {
    return Options(
      headers: {
        'x-api-key': kCurseforgeApiKey,
        'User-Agent': gAppModrinthUserAgent,
      },
    );
  }

  // 获取项目（根据数据源）
  Future<void> _fetchProjects() async {
    if (_dataSource == 'modrinth') {
      await _fetchModrinthProjects();
    } else {
      await _fetchCurseforgeProjects();
    }
  }

  // Modrinth 随机项目
  Future<void> _fetchModrinthProjects() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      LogUtil.log('开始请求Modrinth随机项目', level: 'INFO');
      final response = await DioClient().dio.get(
        'https://api.modrinth.com/v2/projects_random?count=50',
        options: Options(headers: {'User-Agent': gAppModrinthUserAgent})
      );
      if (response.statusCode == 200) {
        LogUtil.log('成功获取Modrinth项目', level: 'INFO');
        _projectsList = response.data;
        await _applyTranslations();
        if (!mounted) return;
        setState(() {
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

  // CurseForge 精选项目
  Future<void> _fetchCurseforgeProjects() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      LogUtil.log('开始请求CurseForge精选项目', level: 'INFO');
      final response = await DioClient().dio.get(
        'https://api.curseforge.com/v1/mods/search',
        queryParameters: {
          'gameId': minecraftGameId,
          'sortField': 2,
          'sortOrder': 'desc',
          'pageSize': 50,
        },
        options: _getCurseforgeOptions(),
      );
      if (response.statusCode == 200) {
        LogUtil.log('成功获取CurseForge项目', level: 'INFO');
        _projectsList = response.data['data'] ?? [];
        await _applyTranslations();
        if (!mounted) return;
        setState(() {
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
    if (query.isEmpty &&
        _modrinthProjectType == null &&
        _curseforgeClassId == null) {
      _fetchProjects();
      return;
    }
    if (_dataSource == 'modrinth') {
      await _searchModrinth(query);
    } else {
      await _searchCurseforge(query);
    }
  }

  // Modrinth 搜索
  Future<void> _searchModrinth(String query) async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
        _isSearching = true;
      });
      final Map<String, dynamic> queryParams = {'query': query};
      if (_modrinthProjectType != null) {
        queryParams['facets'] = '[["project_type:$_modrinthProjectType"]]';
      }
      LogUtil.log(
        '搜索Modrinth项目: $query, 类型: $_modrinthProjectType',
        level: 'INFO',
      );
      final response = await DioClient().dio.get(
        'https://api.modrinth.com/v2/search',
        options: Options(headers: {'User-Agent': gAppModrinthUserAgent}),
        queryParameters: queryParams,
      );
      if (response.statusCode == 200) {
        LogUtil.log('成功获取搜索结果', level: 'INFO');
        _projectsList = response.data['hits'] ?? [];
        await _applyTranslations();
        if (!mounted) return;
        setState(() {
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

  // CurseForge 搜索
  Future<void> _searchCurseforge(String query) async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
        _isSearching = true;
      });
      final Map<String, dynamic> queryParams = {
        'gameId': minecraftGameId,
        'searchFilter': query,
        'sortField': 2,
        'sortOrder': 'desc',
        'pageSize': 50,
      };
      if (_curseforgeClassId != null) {
        queryParams['classId'] = _curseforgeClassId;
      }
      LogUtil.log(
        '搜索CurseForge项目: $query, classId: $_curseforgeClassId',
        level: 'INFO',
      );
      final response = await DioClient().dio.get(
        'https://api.curseforge.com/v1/mods/search',
        queryParameters: queryParams,
        options: _getCurseforgeOptions(),
      );
      if (response.statusCode == 200) {
        LogUtil.log('成功获取搜索结果', level: 'INFO');
        _projectsList = response.data['data'] ?? [];
        await _applyTranslations();
        if (!mounted) return;
        setState(() {
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

  // 调度翻译（根据当前数据源）
  Future<void> _applyTranslations() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    bool autoTranslate = prefs.getBool('autoTranslate') ?? true;
    if (!autoTranslate) return;
    if (_dataSource == 'modrinth') {
      await _applyModrinthTranslations();
    } else {
      await _applyCurseforgeTranslations();
    }
  }

  // Modrinth 批量翻译
  Future<void> _applyModrinthTranslations() async {
    if (_projectsList.isEmpty) return;
    try {
      final ids = _projectsList
          .map((p) => (p['id'] ?? p['project_id'])?.toString())
          .where((id) => id != null)
          .toList();
      if (ids.isEmpty) return;
      LogUtil.log('正在批量获取Modrinth翻译', level: 'INFO');
      final transResponse = await DioClient().dio.post(
        'https://mod.mcimirror.top/translate/modrinth',
        data: {'project_ids': ids},
        options: Options(
          headers: {'User-Agent': gAppModrinthUserAgent},
          validateStatus: (status) => status != null,
        ),
      );
      if (transResponse.statusCode == 200 && transResponse.data is List) {
        final Map<String, String> transMap = {};
        for (final t in transResponse.data as List) {
          if (t['project_id'] != null && t['translated'] != null) {
            transMap[t['project_id'].toString()] = t['translated'].toString();
          }
        }
        if (transMap.isEmpty) return;
        for (final project in _projectsList) {
          final id = (project['id'] ?? project['project_id'])?.toString();
          if (id != null && transMap.containsKey(id)) {
            project['description'] = transMap[id];
          }
        }
        LogUtil.log('Modrinth批量翻译应用成功', level: 'INFO');
      }
    } catch (e) {
      LogUtil.log('Modrinth批量翻译失败: $e', level: 'WARNING');
    }
  }

  // CurseForge 批量翻译
  Future<void> _applyCurseforgeTranslations() async {
    if (_projectsList.isEmpty) return;
    try {
      final ids = _projectsList
          .map((p) => p['id'])
          .where((id) => id != null)
          .cast<int>()
          .toList();
      if (ids.isEmpty) return;
      LogUtil.log('正在批量获取CurseForge翻译', level: 'INFO');
      final transResponse = await DioClient().dio.post(
        'https://mod.mcimirror.top/translate/curseforge',
        data: {'modids': ids},
        options: Options(
          headers: {
            'x-api-key': kCurseforgeApiKey,
            'User-Agent': gAppModrinthUserAgent,
          },
          validateStatus: (status) => status != null,
        ),
      );
      if (transResponse.statusCode == 200 && transResponse.data is List) {
        final Map<int, String> transMap = {};
        for (final t in transResponse.data as List) {
          if (t['modid'] != null && t['translated'] != null) {
            transMap[t['modid'] as int] = t['translated'].toString();
          }
        }
        if (transMap.isEmpty) return;
        for (final project in _projectsList) {
          final id = project['id'] as int?;
          if (id != null && transMap.containsKey(id)) {
            project['summary'] = transMap[id];
          }
        }
        LogUtil.log('CurseForge批量翻译应用成功', level: 'INFO');
      }
    } catch (e) {
      LogUtil.log('CurseForge批量翻译失败: $e', level: 'WARNING');
    }
  }

  // 清除搜索
  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _modrinthProjectType = null;
      _curseforgeClassId = null;
      _isSearching = false;
    });
    _fetchProjects();
  }

  // 切换数据源
  void _switchDataSource(String? source) {
    if (source != null && source != _dataSource) {
      setState(() {
        _dataSource = source;
        _searchController.clear();
        _modrinthProjectType = null;
        _curseforgeClassId = null;
        _isSearching = false;
        _projectsList = [];
      });
      _fetchProjects();
    }
  }

  // 类型标签
  Widget _buildTypeChip(String? type) {
    String? displayName;
    if (_dataSource == 'modrinth') {
      displayName = modrinthProjectTypes[type];
    }
    if (displayName == null) {
      return const SizedBox.shrink();
    }
    return Chip(
      label: Text(displayName),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelStyle: const TextStyle(fontSize: 10),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  // CurseForge 类型标签
  Widget _buildCurseforgeTypeChip(int? classId) {
    if (classId == null || !curseforgeClassIds.containsKey(classId)) {
      return const SizedBox.shrink();
    }
    return Chip(
      label: Text(curseforgeClassIds[classId]!),
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
            // 数据源选择
            Row(
              children: [
                const Text(
                  '数据源',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _dataSource,
                    underline: Container(height: 1),
                    items: const [
                      DropdownMenuItem(
                        value: 'modrinth',
                        child: Text('Modrinth'),
                      ),
                      DropdownMenuItem(
                        value: 'curseforge',
                        child: Text('CurseForge'),
                      ),
                    ],
                    onChanged: _switchDataSource,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12.0),
            // 搜索框
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: _dataSource == 'modrinth'
                    ? '在Modrinth搜索'
                    : '在CurseForge搜索',
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
            // 项目类型选择
            const Text(
              '项目类型',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4.0),
            _dataSource == 'modrinth'
                ? DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text('选择项目类型'),
                    value: _modrinthProjectType,
                    underline: Container(height: 1),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('全部类型'),
                      ),
                      ...modrinthProjectTypes.entries.map(
                        (entry) => DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      ),
                    ],
                    onChanged: (String? newValue) {
                      setState(() {
                        _modrinthProjectType = newValue;
                      });
                      _searchProjects(_searchController.text);
                    },
                  )
                : DropdownButton<int>(
                    isExpanded: true,
                    hint: const Text('选择项目类型'),
                    value: _curseforgeClassId,
                    underline: Container(height: 1),
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text('全部类型'),
                      ),
                      ...curseforgeClassIds.entries.map(
                        (entry) => DropdownMenuItem<int>(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      ),
                    ],
                    onChanged: (int? newValue) {
                      setState(() {
                        _curseforgeClassId = newValue;
                      });
                      _searchProjects(_searchController.text);
                    },
                  ),
          ],
        ),
      ),
    );
  }

  // Modrinth 项目卡片
  Widget _buildModrinthProjectCard(dynamic project) {
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

  // CurseForge 项目卡片
  Widget _buildCurseforgeProjectCard(dynamic project) {
    final logo = project['logo'];
    final classId = project['classId'] as int?;
    final categories = project['categories'] as List?;

    return Card(
      margin: const EdgeInsets.all(8.0),
      child: ListTile(
        leading: logo != null && logo['url'] != null
            ? Image.network(
                logo['url'],
                width: 50,
                height: 50,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.extension, size: 50),
              )
            : const Icon(Icons.extension, size: 50),
        title: Row(
          children: [
            if (classId != null)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: _buildCurseforgeTypeChip(classId),
              ),
            Expanded(
              child: Text(
                project['name'] ?? 'Unknown',
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
            Wrap(
              spacing: 4,
              children: categories != null
                  ? categories
                        .take(3)
                        .map<Widget>(
                          (cat) => Chip(
                            label: Text(cat['name'] ?? ''),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            labelStyle: const TextStyle(fontSize: 10),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList()
                  : [],
            ),
          ],
        ),
        isThreeLine: true,
        onTap: () => Navigator.push(
          context,
          SlidePageRoute(
            page: CurseforgeInfoPage(
              modId: project['id'],
              projectInfo: Map<String, dynamic>.from(project),
            ),
          ),
        ),
      ),
    );
  }

  // 项目卡片（根据数据源选择）
  Widget _buildProjectCard(dynamic project) {
    if (_dataSource == 'modrinth') {
      return _buildModrinthProjectCard(project);
    } else {
      return _buildCurseforgeProjectCard(project);
    }
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
