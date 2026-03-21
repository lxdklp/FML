import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart' show BlockPicker;
import 'package:fml/constants.dart';
import 'package:fml/main.dart';

class ThemePage extends StatefulWidget {
  const ThemePage({super.key});

  @override
  ThemePageState createState() => ThemePageState();
}

class ThemePageState extends State<ThemePage> {
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
              '主题',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),

          _itemsPadding,

          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto),
                  label: Text('跟随系统'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode),
                  label: Text('浅色'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode),
                  label: Text('深色'),
                ),
              ],
              selected: {FMLBaseApp.of(context).themeMode},

              onSelectionChanged: (Set<ThemeMode> newSelection) {
                setState(() {
                  FMLBaseApp.of(context).changeTheme(newSelection.first);
                });
              },
            ),
          ),

          _itemsPadding,

          Card(
            // 裁剪掉ListTile超出圆角的部分
            clipBehavior: Clip.antiAlias,

            elevation: 0,

            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(12),
            ),

            child: ListTile(
              leading: const Icon(Icons.color_lens_outlined),
              title: const Text('主题色'),
              subtitle: const Text('设置配色方案'),
              trailing: CircleAvatar(
                backgroundColor: FMLBaseApp.of(context).themeColor,
                radius: 12,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),

              onTap: () => _selectColor(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectColor() async {
    showDialog(
      context: context,
      builder: (context) {
        final themeColor = FMLBaseApp.of(context).themeColor;

        return AlertDialog(
          title: const Text('选择主题色'),
          content: BlockPicker(
            // 覆写一个ItemBuilder，去除选色圈的阴影背景，更符合MD3
            itemBuilder:
                (
                  Color color,
                  bool isCurrentColor,
                  void Function() changeColor,
                ) {
                  return GestureDetector(
                    onTap: changeColor,
                    child: Container(
                      margin: const EdgeInsets.all(kDefaultPadding / 4),

                      // 添加选中时的框
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isCurrentColor
                            ? Border.all(color: Colors.black38, width: 2)
                            : null,
                      ),
                      width: 40,
                      height: 40,
                    ),
                  );
                },
            pickerColor: themeColor,
            // 不使用自带的颜色
            availableColors: Colors.primaries,

            onColorChanged: (Color color) {
              setState(() {
                FMLBaseApp.of(context).changeThemeColor(color);
              });
            },
          ),

          actions: <Widget>[
            TextButton(
              child: const Text('关闭'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
