import 'package:flutter/material.dart';
import 'dart:io';

class JavaPage extends StatefulWidget {
  const JavaPage({super.key});

  @override
  _JavaPageState createState() => _JavaPageState();
}

class _JavaPageState extends State<JavaPage> {
  String _javaInfo = '正在检测...';

  @override
  void initState() {
    super.initState();
    _checkJava();
  }

  Future<void> _checkJava() async {
    try {
      final result = await Process.run('java', ['-version']);
      if (result.exitCode == 0) {
        setState(() {
          _javaInfo = result.stderr.isNotEmpty
              ? result.stderr
              : result.stdout;
        });
      } else {
        setState(() {
          _javaInfo = '未检测到 Java，请检查是否已安装并配置环境变量。';
        });
      }
    } catch (e) {
      setState(() {
        _javaInfo = '未检测到 Java，请检查是否已安装并配置环境变量。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Java 检测'),
      ),
      body: Center(
        child: Text(_javaInfo),
      ),
    );
  }
}