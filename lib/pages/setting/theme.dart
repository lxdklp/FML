import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart' show BlockPicker;
import 'package:fml/main.dart';

class ThemePage extends StatefulWidget {
  const ThemePage({super.key});

  @override
  ThemePageState createState() => ThemePageState();
}

class ThemePageState extends State<ThemePage> {
  bool _isDarkMode = false;
  bool _followSystem = false;
  Color _themeColor = Colors.blue;

  @override
  void initState() {
    super.initState();
    _isDarkMode = FMLBaseApp.of(context).themeMode == ThemeMode.dark;
    _followSystem = FMLBaseApp.of(context).themeMode == ThemeMode.system;
    _themeColor = FMLBaseApp.of(context).themeColor;
  }

  Future<void> _selectColor() async {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('选择主题色'),
          content: BlockPicker(
            pickerColor: _themeColor,
            onColorChanged: (Color color) {
              setState(() {
                _themeColor = color;
                FMLBaseApp.of(context).changeThemeColor(_themeColor);
              });
            },
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('确定'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('主题设置')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SwitchListTile(
                title: const Text('暗色模式跟随系统'),
                secondary: const Icon(Icons.brightness_6),
                value: _followSystem,
                onChanged: (bool value) {
                  setState(() {
                    _followSystem = value;
                    FMLBaseApp.of(context).changeTheme(
                      _followSystem
                          ? ThemeMode.system
                          : (_isDarkMode ? ThemeMode.dark : ThemeMode.light),
                    );
                  });
                },
              ),
            ),
            if (!_followSystem)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SwitchListTile(
                  title: const Text('暗色模式'),
                  secondary: const Icon(Icons.dark_mode),
                  value: _isDarkMode,
                  onChanged: (bool value) {
                    setState(() {
                      _isDarkMode = value;
                      FMLBaseApp.of(context).changeTheme(
                        _isDarkMode ? ThemeMode.dark : ThemeMode.light,
                      );
                    });
                  },
                ),
              ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: const Text('主题色'),
                leading: const Icon(Icons.color_lens),
                trailing: Container(width: 24, height: 24, color: _themeColor),
                onTap: _selectColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
