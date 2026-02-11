import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:fml/function/dio_client.dart';
import 'package:fml/function/slide_page_route.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fml/pages/download/download_version/download_game.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fml/function/log.dart';

class DownloadVersion extends StatefulWidget {
  const DownloadVersion({super.key});

  @override
  DownloadVersionState createState() => DownloadVersionState();
}

class DownloadVersionState extends State<DownloadVersion> {
  int retry = 3;
  List<dynamic> _versionList = [];
  bool _isLoading = true;
  String? _error;
  bool _showSnapshots = false;
  bool _showOld = false;

  @override
  void initState() {
    super.initState();
    fetchVersionManifest();
  }

  // 获取版本清单
  Future<void> fetchVersionManifest() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      final options = Options(responseType: ResponseType.plain);
      LogUtil.log('开始请求版本清单', level: 'INFO');
      final response = await DioClient().dio.get(
        'https://bmclapi2.bangbang93.com/mc/game/version_manifest.json',
        options: options,
      );
      if (response.statusCode == 200) {
        LogUtil.log('成功获取版本清单', level: 'INFO');
        try {
          final rawData = response.data;
          dynamic parsedData;
          if (rawData is String) {
            try {
              parsedData = jsonDecode(rawData);
            } catch (jsonError) {
              LogUtil.log('JSON解析失败: $jsonError', level: 'ERROR');
              throw Exception('JSON解析失败: $jsonError');
            }
          } else if (rawData is Map) {
            parsedData = rawData;
          } else {
            LogUtil.log('意外的数据类型: ${rawData.runtimeType}', level: 'ERROR');
            throw Exception('意外的响应数据类型: ${rawData.runtimeType}');
          }
          if (parsedData == null) {
            throw Exception('解析后的数据为空');
          }
          if (!parsedData.containsKey('versions')) {
            LogUtil.log('数据缺少versions字段', level: 'ERROR');
            throw Exception('返回数据中缺少versions字段');
          }
          final versions = parsedData['versions'];
          if (versions is! List) {
            LogUtil.log(
              'versions不是列表类型: ${versions.runtimeType}',
              level: 'ERROR',
            );
            throw Exception('versions字段格式错误');
          }
          LogUtil.log('成功解析版本数据，共${versions.length}个版本', level: 'INFO');
          setState(() {
            _versionList = versions;
            _isLoading = false;
          });
        } catch (parseError) {
          LogUtil.log('解析版本清单时出错: $parseError', level: 'ERROR');
          setState(() {
            _error = '无法解析版本数据: $parseError 可能是网络或者服务器问题,请稍后再试';
            _isLoading = false;
          });
        }
      } else {
        LogUtil.log('请求失败：状态码 ${response.statusCode}', level: 'ERROR');
        setState(() {
          _error = '请求失败：状态码 ${response.statusCode} 可能是网络或者服务器问题,请稍后再试';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      LogUtil.log('请求出错: $e', level: 'ERROR');
      setState(() {
        _error = '网络请求失败: $e 可能是网络或者服务器问题,请稍后再试';
        _isLoading = false;
        retry -= 1;
      });
      if (retry > 0) {
        LogUtil.log('正在重试请求，剩余重试次数: $retry', level: 'INFO');
        await fetchVersionManifest();
      }
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

  // 检查选择目录
  Future<void> _checkSelectedPath(id, url, type) async {
    final prefs = await SharedPreferences.getInstance();
    final selectedDir = prefs.getString('SelectedPath');
    if (!mounted) return;
    if (selectedDir == null || selectedDir.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择下载目录')));
    } else {
      LogUtil.log('选择了版本: $id - URL: $url', level: 'INFO');
      Navigator.push(
        context,
        SlidePageRoute(
          page: DownloadGamePage(type: type, version: id, url: url),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error!),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _isLoading = true;
                        _error = null;
                      });
                      fetchVersionManifest();
                    },
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : ListView(
              children: [
                Card(
                  child: ListTile(
                    title: const Text('下载由 BMCLAPI 提供'),
                    subtitle: const Text('赞助 BMCLAPI 喵~ 赞助 BMCLAPI 谢谢喵~ '),
                    leading: const Icon(Icons.info),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => _launchURL('https://bmclapi.bangbang93.com/'),
                  ),
                ),
                Card(
                  child: SwitchListTile(
                    title: const Text('显示快照版本'),
                    value: _showSnapshots,
                    onChanged: (value) {
                      setState(() {
                        _showSnapshots = value;
                      });
                    },
                  ),
                ),
                Card(
                  child: SwitchListTile(
                    title: const Text('显示远古版本'),
                    value: _showOld,
                    onChanged: (value) {
                      setState(() {
                        _showOld = value;
                      });
                    },
                  ),
                ),
                ..._versionList
                    .where(
                      (dynamic version) =>
                          _showSnapshots ||
                          version['type'] != 'snapshot' &&
                              (_showOld ||
                                  (version['type'] != 'old_alpha' &&
                                      version['type'] != 'old_beta')),
                    )
                    .map(
                      (dynamic version) => Card(
                        child: ListTile(
                          title: Text(version['id']),
                          subtitle: Text(
                            '类型: ${version['type']} - 发布时间: ${_formatDate(version['releaseTime'])}',
                          ),
                          leading: Icon(
                            version['type'] == 'release'
                                ? Icons.check_circle
                                : Icons.science,
                          ),
                          onTap: () {
                            _checkSelectedPath(
                              version['id'],
                              version['url'],
                              version['type'],
                            );
                          },
                        ),
                      ),
                    ),
              ],
            ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return isoDate;
    }
  }
}
