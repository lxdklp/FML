import 'package:material_ui/material_ui.dart';
import 'dart:io';

import 'package:fml/pages/home/management/saves_management/save/save_info.dart';
import 'package:fml/pages/home/management/saves_management/save/save_backups.dart';

class SavePage extends StatefulWidget {
  final String savePath;
  final String saveName;

  const SavePage({
    super.key,
    required this.savePath,
    required this.saveName,
    });

  @override
  SavePageState createState() => SavePageState();
}

class SavePageState extends State<SavePage> with TickerProviderStateMixin {
  late TabController _tabController;

  // 检查与创建备份文件夹
  Future<void> _checkBackupFolder() async {
    final backupDir = Directory('${widget.savePath}/backups');
    if (!await backupDir.exists()) {
      await backupDir.create();
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkBackupFolder();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.saveName),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '存档信息'),
            Tab(text: '备份管理'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SaveInfoTab(savePath: widget.savePath, saveName: widget.saveName),
          SaveBackupsTab(savePath: widget.savePath),
        ],
      ),
    );
  }
}