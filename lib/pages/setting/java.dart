import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fml/constants.dart';
import 'package:fml/function/java/java_service.dart';
import 'package:fml/function/java/java_utils.dart';
import 'package:fml/function/java/models/java_info.dart';
import 'package:fml/function/java/models/java_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

class JavaPage extends StatefulWidget {
  const JavaPage({super.key});

  @override
  JavaPageState createState() => JavaPageState();
}

class JavaPageState extends State<JavaPage> {
  // 每个设置间的间距
  static const _itemsPadding = Padding(
    padding: EdgeInsets.symmetric(vertical: kDefaultPadding / 2),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kDefaultPadding),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          // 大标题
          Row(
            // 使按钮组紧贴
            mainAxisSize: MainAxisSize.min,

            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: kDefaultPadding / 2,
                  top: kDefaultPadding,
                  bottom: kDefaultPadding,
                ),

                child: Text(
                  '设备上的Java列表',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),

              Spacer(),

              IconButton(
                icon: const Icon(Icons.add),
                tooltip: '手动添加一个Java',
                onPressed: () async => await _pickAndAddJavaRuntime(),
              ),
            ],
          ),

          _itemsPadding,

          // 确保ListView占满剩余空间
          Expanded(
            child: ListView.builder(
              itemCount: JavaService.javaRuntimes.length,
              itemBuilder: (context, index) {
                // 构建Java的卡片
                final javaRuntime = JavaService.javaRuntimes[index];

                final isCurrentJava =
                    JavaService.currentJavaPath == javaRuntime.executable;

                final isSystemDefault =
                    javaRuntime.executable ==
                    JavaService.systemDefaultJavaInfo?.path;

                return _buildJavaCard(
                  javaInfo: javaRuntime.info,

                  typeChipLabel: javaRuntime.isJdk ? 'JDK' : 'JRE',

                  vendor: javaRuntime.info.vendor,

                  isCurrent: isCurrentJava,

                  isSystemDefault: isSystemDefault,

                  onTap: () => {
                    setState(() {
                      JavaService.setSelectedJavaPathToPrefs(
                        javaRuntime.executable,
                      );
                    }),
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  ///
  /// 显示FilePicker并根据选择的文件添加JavaRuntimes
  ///
  Future<void> _pickAndAddJavaRuntime() async {
    // 打开FilePicker
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择Java路径',
      type: FileType.custom,
      allowedExtensions: Platform.isWindows ? ['exe'] : [],
    );

    if (!mounted) return;

    // 未选择文件
    if (result == null) {
      showCustomDialog(
        context: context,
        title: '提示',

        content: Text('未选择任何文件'),

        actions: [
          if (mounted)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('关闭'),
            ),
        ],
      );

      return;
    }

    // 读取选择的文件的信息
    final file = result.files.single;
    final fileName = file.name.toLowerCase();
    final validNames = Platform.isWindows
        ? ['java.exe', 'javaw.exe']
        : ['java', 'javaw'];

    final exe = file.path!;
    final info = await JavaUtils.probeJavaExecutable(exe);

    // 选择的文件文件名合法
    if (file.path != null && validNames.contains(fileName)) {
      if (!mounted) return;

      showCustomDialog(
        context: context,
        title: '正在添加Java',
        content: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),

        barrierDismissible: false,
      );

      if (info != null) {
        // 查重逻辑
        final alreadyExists = JavaService.javaRuntimes.any(
          (runtime) => runtime.executable == exe,
        );

        if (alreadyExists) {
          Navigator.of(context).pop();

          showCustomDialog(
            context: context,
            title: '提示',

            content: Text('该Java已存在'),

            actions: [
              if (mounted)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('关闭'),
                ),
            ],
          );

          return;
        }

        // 添加并写入SharedPreference
        final isJdk = await JavaUtils.looksLikeJdk(exe);

        JavaService.javaRuntimes.add(
          JavaRuntime(info: info, executable: exe, isJdk: isJdk),
        );

        JavaService.writeRuntimesToPrefs(
          await SharedPreferences.getInstance(),
          JavaService.javaRuntimes,
        );

        Navigator.of(context).pop();

        // 仅添加成功会有页面更新，故只在此处调用setState
        setState(() {
          showCustomDialog(
            context: context,
            title: '提示',
            content: Text('添加 ${info.vendor} ${info.version} 成功！'),

            actions: [
              if (mounted)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('关闭'),
                ),
            ],
          );
        });

        return;
      }
    }

    // 最后分支，选择的文件文件名不合法等情况
    if (!mounted) return;

    Navigator.of(context).maybePop();

    showCustomDialog(
      context: context,
      title: '提示',
      content: Text('请选择正确的Java可执行文件'),

      actions: [
        TextButton(
          onPressed: () => {if (mounted) Navigator.of(context).pop()},
          child: Text('关闭'),
        ),
      ],
    );
  }

  ///
  /// 显示一个自定义的AlertDialog
  ///
  void showCustomDialog({
    required BuildContext context,
    required String title,
    Widget? content,
    bool barrierDismissible = true,
    List<Widget>? actions,
  }) {
    showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) =>
          AlertDialog(title: Text(title), content: content, actions: actions),
    );
  }

  Widget _buildJavaCard({
    required JavaInfo javaInfo,
    required String typeChipLabel,
    String? vendor,
    required bool isCurrent,
    required bool isSystemDefault,
    required VoidCallback onTap,
  }) {
    return Card(
      // 裁剪掉ListTile超出圆角的部分
      clipBehavior: Clip.antiAlias,

      elevation: 0,

      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),

      // 为当前Java时高亮
      color: isCurrent
          ? Theme.of(context).colorScheme.secondaryContainer
          : null,

      child: ListTile(
        title: Text(javaInfo.version),

        subtitle: Text(javaInfo.path.isNotEmpty ? javaInfo.path : '路径未知'),

        trailing: Row(
          mainAxisSize: MainAxisSize.min,

          children: [
            if (isCurrent) ...[
              Chip(label: Text('当前')),

              SizedBox(width: kDefaultPadding / 2),
            ],

            if (isSystemDefault) ...[
              Chip(label: Text('系统默认')),

              SizedBox(width: kDefaultPadding / 2),
            ],

            Chip(label: Text(typeChipLabel)),

            SizedBox(width: kDefaultPadding / 2),

            Chip(label: Text(vendor ?? 'Unknown')),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
