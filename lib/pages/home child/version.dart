import 'package:flutter/material.dart';

class VersionPage extends StatefulWidget {
  const VersionPage({super.key});

  @override
  _VersionPageState createState() => _VersionPageState();
}

class _VersionPageState extends State<VersionPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
      ),
      body: const Center(
        child: Text('版本'),
      ),
    );
  }
}