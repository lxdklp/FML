import 'package:flutter/material.dart';
import 'package:fml/pages/download child/loader/DownloadVanilla.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadGamePage extends StatefulWidget {
  DownloadGamePage({super.key, required this.type, required this.version, required this.url});

  final String type;
  final String version;
  final String url;
  List<String> _VersionList = [];

  @override
  _DownloadGamePageState createState() => _DownloadGamePageState();
}

class _DownloadGamePageState extends State<DownloadGamePage> {
  String _selectedLoader = 'Vanilla';
  late final TextEditingController _gameNameController;
  String _gameName = '';
  List<String> _VersionList = [];

  // 读取版本列表
  Future<void> _loadVersionList() async {
    final prefs = await SharedPreferences.getInstance();
    final _SelectedPath = prefs.getString('SelectedPath') ?? '';
    final _GameList = prefs.getStringList('Game_$_SelectedPath') ?? [];
    setState(() {
      _VersionList = _GameList;
    });
  }

  @override
  void initState() {
    super.initState();
    _gameNameController = TextEditingController();
    _gameNameController.text = widget.version;
    _gameName = widget.version;
    _loadVersionList();
  }

  @override
  void dispose() {
    _gameNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('下载${widget.version}'),
      ),
      body: Center(
        child: ListView(
          children: [
            Card(
              child: ListTile(
                title: Text('版本: ${widget.version}'),
                subtitle: Text('类型: ${widget.type}'),
                leading: Icon(
                  widget.type == 'release' ? Icons.check_circle : Icons.science,
                ),
              ),
            ),
            Card(
              child: TextField(
                controller: _gameNameController,
                decoration: InputDecoration(
                  labelText: '游戏名称',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() {
                  _gameName = value;
                }),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('模组加载器'),
                    DropdownButton<String>(
                      value: _selectedLoader,
                      hint: const Text('选择模组加载器'),
                      items: [
                        DropdownMenuItem<String>(
                          value: 'Vanilla',
                          child: const Text('不安装模组加载器'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'Fabric',
                          child: const Text('Fabric'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'NeoForge',
                          child: const Text('NeoForge'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedLoader = value!;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (_selectedLoader == 'Fabric') ...[
              Card(
                child: ListTile(
                  title: Text('Fabric特有设置'),
                ),
              ),
            ],
            if (_selectedLoader == 'NeoForge') ...[
              Card(
                child: ListTile(
                  title: Text('NeoForge特有设置'),
                ),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_gameName.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('游戏名称不能为空')),
            );
            return;
          }
          if (_VersionList.contains(_gameName)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('该游戏名称已存在，请换一个名称')),
            );
            return;
          }
          if (_selectedLoader == 'Vanilla') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => DownloadVanillaPage(version: widget.version, url: widget.url, name: _gameName)),
            );
          } else {
          }
        },
        child: const Icon(Icons.download),
      ),
    );
  }
}