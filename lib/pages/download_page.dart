import 'package:flutter/material.dart';
import 'package:fml/constants.dart';
import 'package:fml/pages/download/download_resources.dart';
import 'package:fml/pages/download/download_version.dart';
import 'package:fml/pages/model/navigation_drawer_item.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  DownloadPageState createState() => DownloadPageState();
}

class DownloadPageState extends State<DownloadPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<NavigationDrawerItem> downloadPageItems = [
      NavigationDrawerItem(
        page: const DownloadVersionPage(),
        destination: NavigationDrawerDestination(
          icon: const Icon(Icons.code, fill: 1),
          label: Text('游戏'),
        ),
      ),
      NavigationDrawerItem(
        page: const DownloadResources(),
        destination: NavigationDrawerDestination(
          icon: const Icon(Icons.extension, fill: 1),
          label: Text('资源'),
        ),
      ),
    ];

    ThemeData theme = Theme.of(context);

    return Material(
      child: Row(
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
                  child: Text('下载', style: theme.textTheme.headlineMedium),
                ),

                // Destinations
                for (var item in downloadPageItems) item.destination,
              ],
            ),
          ),

          // 显示当前选择的页面
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: downloadPageItems.map((item) => item.page).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
