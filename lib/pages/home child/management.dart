import 'package:flutter/material.dart';

class ManagementPage extends StatefulWidget {
  const ManagementPage({super.key});

  @override
  _ManagementPageState createState() => _ManagementPageState();
}

class _ManagementPageState extends State<ManagementPage> {
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