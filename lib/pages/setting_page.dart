import 'package:flutter/material.dart';
import 'package:fml/constants.dart';
import 'package:fml/models/page/navigation_drawer_item.dart';
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
  int _selectedIndex = 0;

  final List<NavigationDrawerItem> _settingPageItems = const [
    NavigationDrawerItem(
      page: ThemePage(),
      destination: NavigationDrawerDestination(
        icon: Icon(Icons.imagesearch_roller),
        label: Text('主题'),
      ),
    ),
    NavigationDrawerItem(
      page: JavaPage(),
      destination: NavigationDrawerDestination(
        icon: Icon(Icons.code),
        label: Text('Java管理'),
      ),
    ),
    NavigationDrawerItem(
      page: LogViewerPage(),
      destination: NavigationDrawerDestination(
        icon: Icon(Icons.receipt_long),
        label: Text('APP日志'),
      ),
    ),
    NavigationDrawerItem(
      page: AboutPage(),
      destination: NavigationDrawerDestination(
        icon: Icon(Icons.info),
        label: Text('关于'),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);

    return Material(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 动态设置sidebar宽度
          // clamp限制最大最小值
          double sidebarWidth = (constraints.maxWidth * 0.25).clamp(
            150.0,
            320.0,
          );

          return Row(
            mainAxisAlignment: MainAxisAlignment.start,

            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: theme.dividerColor.withAlpha(100)),
                  ),
                ),

                // 用SizedBox包裹NavigationDrawer避免宽度过大
                child: SizedBox(
                  width: sidebarWidth,
                  child: NavigationDrawer(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (index) {
                      if (_selectedIndex == index) return;
                      // 移除当前上下文中的所有焦点，避免视觉残留
                      FocusScope.of(context).unfocus();

                      setState(() {
                        _selectedIndex = index;
                      });
                    },

                    children: [
                      Padding(
                        // 将文字与Destination对齐
                        padding: const EdgeInsets.fromLTRB(
                          kDefaultPadding * 1.5,
                          kDefaultPadding,
                          kDefaultPadding,
                          kDefaultPadding,
                        ),
                        child: Text(
                          '设置',
                          style: theme.textTheme.headlineMedium,
                        ),
                      ),

                      // Destinations
                      for (var item in _settingPageItems) item.destination,
                    ],
                  ),
                ),
              ),

              // 显示当前选择的页面
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: _settingPageItems.map((item) => item.page).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
