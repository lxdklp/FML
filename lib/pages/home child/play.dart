import 'package:flutter/material.dart';
import 'package:fml/function/launcher/vanilla.dart';
import 'package:fml/function/launcher/fabric.dart';

class PlayPage extends StatefulWidget {
  const PlayPage({super.key});

  @override
  _PlayPageState createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage> {
  @override
  void initState() {
    super.initState();
    vanillaLauncher();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('正在启动游戏'),
      ),
      body: const Center(
        child: Text(''),
      ),
    );
  }
}