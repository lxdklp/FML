import 'package:flutter/material.dart';
import 'package:system_info2/system_info2.dart';

class addVersionPage extends StatefulWidget {
  const addVersionPage({super.key});

  @override
  _addVersionPageState createState() => _addVersionPageState();
}

class _addVersionPageState extends State<addVersionPage> {

  int _mem = 1;
  String path = '';
  int _xms = 0;
  int _xmx = 0;

  @override
  void initState() {
    super.initState();
    _getMemory();
  }

  /// 获取系统总内存
  void _getMemory(){
    int bytes = SysInfo.getTotalPhysicalMemory();
    // 内存错误修正
    if (bytes > (1024 * 1024 * 1024 * 1024) && bytes % 16384 == 0) {
      bytes = bytes ~/ 16384;
    }
    final physicalMemory = bytes ~/ (1024 * 1024 * 1024);
    setState(() {
      _mem = physicalMemory;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入本地文件'),
      ),
      body: Center(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: '输入本地游戏JAR',
                  prefixIcon: Icon(Icons.file_present),
                  border: OutlineInputBorder()
                ),
                onSubmitted: (value) {
                  // 在这里处理输入的游戏JAR路径
                },
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                decoration: InputDecoration(
                  labelText: '-Xms(JVM初始内存)',
                  prefixIcon: const Icon(Icons.memory),
                  hintText: '${_mem ~/ 8}G',
                  border: const OutlineInputBorder()
                ),
                onSubmitted: (value) {
                  if (value.isEmpty) {
                    _xms = _mem ~/ 8;
                  }
                },
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                decoration: InputDecoration(
                  labelText: '-Xmx(JVM最大内存)',
                  prefixIcon: const Icon(Icons.memory),
                  hintText: '${_mem ~/ 2}G',
                  border: const OutlineInputBorder()
                ),
                onSubmitted: (value) {
                  if (value.isEmpty) {
                    _xmx = _mem ~/ 2;
                  }
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('版本已导入')),
          );
        },
        child: const Icon(Icons.save),
      ),
    );
  }
}