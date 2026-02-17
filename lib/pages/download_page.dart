import 'package:flutter/material.dart';
import 'package:fml/constants.dart';
import 'package:fml/pages/download/download_resources.dart';
import 'package:fml/pages/download/download_version.dart';
import 'package:fml/models/page/navigation_drawer_item.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  DownloadPageState createState() => DownloadPageState();
}

class DownloadPageState extends State<DownloadPage> {
  int _selectedIndex = 0;

  final List<NavigationDrawerItem> _downloadPageItems = const [
    NavigationDrawerItem(
      page: DownloadVersionPage(),
      destination: NavigationDrawerDestination(
        icon: Icon(Icons.code),
        label: Text('游戏'),
      ),
    ),
    NavigationDrawerItem(
      page: DownloadResources(),
      destination: NavigationDrawerDestination(
        icon: Icon(Icons.extension),
        label: Text('资源'),
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
              // const VerticalDivider(),
              // 添加VerticalDivider会导致一个意外的间距，所以这里使用了一个Container
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
                          '下载',
                          style: theme.textTheme.headlineMedium,
                        ),
                      ),

                      // Destinations
                      for (var item in _downloadPageItems) item.destination,
                    ],
                  ),
                ),
              ),

              // 显示当前选择的页面
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: _downloadPageItems
                      .map((item) => item.page)
                      .toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
