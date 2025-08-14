import 'package:flutter/material.dart';
import 'dart:convert'; // 添加JSON转换支持
import 'dart:io'; // 添加文件操作支持
import 'package:path_provider/path_provider.dart'; // 添加路径获取支持

class DownloadTestPage extends StatefulWidget {
  const DownloadTestPage({super.key, required this.version, required this.url, required this.name, required this.fabricVersion, required this.fabricLoader});

  final String version;
  final String url;
  final String name;
  final String fabricVersion;
  final Map<String, dynamic>? fabricLoader;

  @override
  _DownloadTestPageState createState() => _DownloadTestPageState();
}

class _DownloadTestPageState extends State<DownloadTestPage> {
  @override
  void initState() {
    debugPrint(widget.fabricLoader.toString());
    saveLoaderToJson(); // 初始化时保存JSON
    super.initState();
  }
  
  // 添加保存JSON到本地的方法
  Future<void> saveLoaderToJson() async {
    try {
      if (widget.fabricLoader == null) {
        debugPrint('fabricLoader为空，无法保存');
        return;
      }
      final String jsonString = jsonEncode(widget.fabricLoader);
      final String dirPath = '/Users/lxdklp/.minecraft';
      final String filePath = '$dirPath/fabric_loader.json';
      
      // 检查目录是否存在，不存在则创建
      final Directory directory = Directory(dirPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
        debugPrint('已创建目录: $dirPath');
      }
      
      // 创建文件并写入JSON内容
      final File file = File(filePath);
      await file.writeAsString(jsonString);
      
      debugPrint('已成功将fabricLoader保存到: $filePath');
    } catch (e) {
      debugPrint('保存JSON时出错: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('版本: ${widget.version}\nURL: ${widget.url}\n名称: ${widget.name}\nFabric版本: ${widget.fabricVersion}\nFabric加载器: ${widget.fabricLoader}'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: saveLoaderToJson,
              child: const Text('保存Loader数据到本地'),
            ),
          ],
        ),
      ),
    );
  }
}