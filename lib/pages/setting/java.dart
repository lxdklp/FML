import 'package:flutter/material.dart';
import 'package:fml/constants.dart';
import 'package:fml/function/java/java_service.dart';
import 'package:fml/function/java/models/java_info.dart';

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

          _itemsPadding,

          // 确保FutureBuilder占满剩余空间
          Expanded(
            child: ListView.builder(
              itemCount: JavaService.javaRuntimes.length,
              itemBuilder: (context, index) {
                // 构建Java的卡片
                final javaRuntime = JavaService.javaRuntimes[index];

                final isCurrentJava =
                    JavaService.currentJavaPath == javaRuntime.executable;

                return _buildJavaCard(
                  javaInfo: javaRuntime.info,

                  typeChipLabel: javaRuntime.isJdk ? 'JDK' : 'JRE',

                  vendor: javaRuntime.info.vendor,

                  isCurrent: isCurrentJava,

                  onTap: () => {
                    setState(() {
                      JavaService.setCurrentJavaPathToPrefs(
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

  Widget _buildJavaCard({
    required JavaInfo javaInfo,
    required String typeChipLabel,
    String? vendor,
    required bool isCurrent,
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
