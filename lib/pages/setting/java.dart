import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fml/constants.dart';
import 'package:fml/function/java/java_service.dart';
import 'package:fml/function/java/java_utils.dart';
import 'package:fml/function/java/models/java_info.dart';
import 'package:fml/function/java/models/java_runtime.dart';
import 'package:open_filex/open_filex.dart';

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

  bool _isRefreshing = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kDefaultPadding),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          // 大标题
          Row(
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
                icon: const Icon(Icons.refresh),
                tooltip: '刷新',
                onPressed: _isRefreshing
                    ? null
                    : () async {
                        setState(() => _isRefreshing = true);

                        try {
                          // 在子线程获取数据
                          final searchResults = await Isolate.run(
                            () => JavaUtils.searchPotentialJavaExecutables(),
                          );

                          // 将javaRuntimes转换为Map
                          final Map<String, JavaRuntime> runtimeMap = {
                            for (var runtime in JavaService.javaRuntimes)
                              runtime.executable: runtime,
                          };

                          // 通过Map查重
                          int addedCount = 0;
                          for (var result in searchResults) {
                            if (!runtimeMap.containsKey(result.executable)) {
                              runtimeMap[result.executable] = result;
                              // 发现新Java时计数
                              addedCount++;
                            }
                          }

                          final totalList = runtimeMap.values.toList();

                          // 更新并写入
                          await JavaService.updateJavaRuntimes(totalList);

                          if (!mounted) return;

                          String message = addedCount > 0
                              ? '刷新完成，搜索到了$addedCount个Java（共有${totalList.length}个）'
                              : '刷新完成，未发现新的Java (共有${totalList.length}个)';

                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(message)));
                        } finally {
                          if (mounted) setState(() => _isRefreshing = false);
                        }
                      },
              ),

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
            child: _isRefreshing
                ? Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: JavaService.javaRuntimes.length,
                    itemBuilder: (context, index) {
                      // 构建Java的卡片
                      final javaRuntime = JavaService.javaRuntimes[index];

                      final isCurrentJava =
                          JavaService.javaSelectedPath ==
                          javaRuntime.executable;

                      final isSystemDefault =
                          javaRuntime.executable ==
                          JavaService.systemDefaultJavaInfo?.path;

                      return _buildJavaCard(
                        javaInfo: javaRuntime.info,

                        typeChipLabel: javaRuntime.isJdk ? 'JDK' : 'JRE',

                        vendor: javaRuntime.info.vendor,

                        isCurrent: isCurrentJava,

                        isSystemDefault: isSystemDefault,

                        onTap: () async => {
                          // 异步更新数据
                          await JavaService.updateJavaSelectedPath(
                            javaRuntime.executable,
                          ),

                          // 通知UI刷新
                          if (mounted) {setState(() {})},
                        },

                        onLongPress: () =>
                            _buildOnLongPressDialog(context, javaRuntime),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _buildOnLongPressDialog(
    BuildContext context,
    JavaRuntime javaRuntime,
  ) async {
    await showDialog(
      context: context,

      builder: (context) {
        return SimpleDialog(
          title: Text('选择要进行的操作'),

          children: <Widget>[
            SimpleDialogOption(
              child: Text('在文件资源管理器中显示父文件夹'),
              onPressed: () {
                // 打开父文件夹
                final parentDirPath = File(javaRuntime.executable).parent.path;

                OpenFilex.open(parentDirPath);

                Navigator.of(context).pop();
              },
            ),

            Divider(),

            SimpleDialogOption(
              child: Text('在列表中删除'),

              onPressed: () {
                final javaName =
                    '${javaRuntime.info.vendor} ${javaRuntime.info.version}';

                showCustomDialog(
                  context: context,
                  title: '提示',
                  barrierDismissible: false,

                  content: Text('你确认要在列表中删除 $javaName 吗？'),

                  actions: [
                    TextButton(
                      onPressed: () async {
                        if (!mounted) return;

                        // 弹出当前Dialog
                        Navigator.of(context).maybePop();

                        if (JavaService.javaRuntimes.length <= 1) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('该Java为最后一个Java，无法移除！')),
                          );

                          return;
                        }

                        final wasSelected =
                            JavaService.javaSelectedPath ==
                            javaRuntime.executable;

                        // 从列表中移除
                        JavaService.javaRuntimes.remove(javaRuntime);

                        // 刷新UI 并执行异步操作
                        setState(() {});

                        await JavaService.updateJavaRuntimes(
                          JavaService.javaRuntimes,
                        );

                        if (!mounted) return;

                        // 若移除的为当前Java，将第一个设置为javaRuntimes的第一个
                        if (wasSelected &&
                            JavaService.javaRuntimes.isNotEmpty) {
                          await JavaService.updateJavaSelectedPath(
                            JavaService.javaRuntimes.first.executable,
                          );
                        }

                        // 显示SnackBar并弹出父Dialog
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已从列表中移除 $javaName')),
                        );

                        Navigator.of(context).maybePop();
                      },

                      child: Text('是'),
                    ),

                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text('否'),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
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

    final path = file.path!;

    // 选择的文件文件名不合法等
    if (!validNames.contains(fileName)) {
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

      return;
    }

    if (!mounted) return;

    // 获取规范化的真实物理路径
    final resolvedPath = File(path).resolveSymbolicLinksSync();

    // 查重
    final alreadyExists = JavaService.javaRuntimes.any(
      (runtime) => runtime.executable == resolvedPath,
    );

    if (alreadyExists) {
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

    // 开始添加Java，弹出加载对话框
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

    // 解析Info
    try {
      final info = await JavaUtils.probeJavaExecutable(resolvedPath);

      if (info == null) {
        throw '无法解析Java版本信息，请检查Java是否有效';
      }

      // 解析成功，添加并写入SharedPreference
      final isJdk = await JavaUtils.looksLikeJdk(resolvedPath);

      JavaService.javaRuntimes.add(
        JavaRuntime(info: info, executable: resolvedPath, isJdk: isJdk),
      );

      JavaService.updateJavaRuntimes(JavaService.javaRuntimes);

      if (mounted) Navigator.of(context).pop();

      // 调用setState触发页面更新
      setState(() {});

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
    } catch (e) {
      // 有异常，先关闭 Loading
      if (mounted) Navigator.of(context).pop();

      showCustomDialog(
        context: context,
        title: '错误',

        content: Text('添加Java时发生异常: $e'),

        actions: [
          if (mounted)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('关闭'),
            ),
        ],
      );
    }
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
    required VoidCallback onLongPress,
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
        onLongPress: onLongPress,
      ),
    );
  }
}
