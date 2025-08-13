import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fml/pages/download%20child/DownloadGame.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  _DownloadPageState createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final Dio dio = Dio();
  List<dynamic> _versionList = [];
  bool _isLoading = true;
  String? _error;
  String _appVersion = "unknown";
  bool _showSnapshots = false;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final version = prefs.getString('version') ?? "1.0.0";
    setState(() {
      _appVersion = version;
    });
    fetchVersionManifest();
  }

  Future<void> fetchVersionManifest() async {
    try {
      final options = Options(
        headers: {
          'User-Agent': 'FML/$_appVersion',
        },
      );

      // FML UA请求BMCLAPI
      final response = await dio.get(
        'https://bmclapi2.bangbang93.com/mc/game/version_manifest.json',
        options: options,
      );
      if (response.statusCode == 200) {
        setState(() {
          _versionList = response.data['versions'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = '请求失败：状态码 ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '请求出错: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _isLoading = true;
                _error = null;
              });
              fetchVersionManifest();
            },
          )
        ],
      ),
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
                ..._versionList
                    .where((version) => _showSnapshots || version['type'] != 'snapshot')
                    .map(
                      (version) => Card(
                        child: ListTile(
                          title: Text(version['id']),
                          subtitle: Text('类型: ${version['type']} - 发布时间: ${_formatDate(version['releaseTime'])}'),
                          leading: Icon(
                        version['type'] == 'release' ? Icons.check_circle : Icons.science,
                      ),
                      onTap: () {
                        debugPrint('选择了版本: ${version['id']} - URL: ${version['url']}');
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DownloadGamePage(type: version['type'], version: version['id'], url: version['url']),
                          ),
                        );
                      },
                    ),
                  ),
                )
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