import 'package:flutter/material.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:fml/pages/setting/theme.dart';
import 'package:fml/pages/setting/log_viewer.dart';
import 'package:fml/pages/setting/about.dart';
import 'package:fml/pages/setting/java.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  SettingPageState createState() => SettingPageState();
}

class SettingPageState extends State<SettingPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
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
                    SlidePageRoute(page: const ThemePage()),
                  );
                },
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: Text('\n Java 管理 \n'),
                leading: Icon(Icons.code),
                onTap: () {
                  Navigator.push(
                    context,
                    SlidePageRoute(page: const JavaPage()),
                  );
                },
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: Text('\n APP日志 \n'),
                leading: Icon(Icons.receipt_long),
                onTap: () {
                  Navigator.push(
                    context,
                    SlidePageRoute(page: const LogViewerPage()),
                  );
                },
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: Text('\n 关于 \n'),
                leading: Icon(Icons.info),
                onTap: () {
                  Navigator.push(
                    context,
                    SlidePageRoute(page: const AboutPage()),
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
