import 'package:flutter/material.dart';
import 'package:fml/launcher/vanilla.dart';
import 'package:fml/launcher/fabric.dart';

class PlayPage extends StatefulWidget {
  const PlayPage({super.key});

  @override
  _PlayPageState createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage> {
  @override
  void initState() {
    super.initState();
    fabricLauncher();
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