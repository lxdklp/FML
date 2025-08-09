import 'package:flutter/material.dart';

import 'package:fml/pages/setting child/theme.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  _SettingPageState createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
      ),
      body: Center(
        child: ListView(
          children: [
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: Text('\n 主题设置 \n'),
                leading: Icon(Icons.imagesearch_roller),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => ThemePage()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}