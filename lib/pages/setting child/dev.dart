import 'package:flutter/material.dart';
import 'dart:io';
import 'package:system_info2/system_info2.dart';
import 'package:fml/function/ExtractNatives.dart'; // 确保这个文件存在

class devPage extends StatefulWidget {
  const devPage({super.key});

  @override
  _devPageState createState() => _devPageState();
}


class _devPageState extends State<devPage> {
  @override
  void initState() {
    super.initState();
    ExtractNatives('/Users/lxdklp/Desktop/.minecraft/libraries/org/lwjgl/lwjgl/3.3.3', 'lwjgl-3.3.3-natives-macos-arm64.jar', '/Users/lxdklp/Desktop/1');
      }

  @override
  Widget build(BuildContext context) {
    final String systemName = Platform.operatingSystem; // e.g. linux, macos, windows
    final String kernelName = SysInfo.kernelName; // from system_info2
    final String kernelArch = SysInfo.kernelArchitecture.toString(); // from system_info2


    return Scaffold(
      appBar: AppBar(
        title: const Text('系统信息'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('系统名称: $systemName', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text('内核名称: ${SysInfo.kernelName}', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text('内核架构: $kernelArch', style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}