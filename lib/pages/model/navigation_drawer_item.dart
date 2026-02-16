import 'package:flutter/material.dart';

///
/// 表示导航抽屉中的一个项目
///
/// 持有一个导航到的页面[page]以及[NavigationDrawerDestination]
///
class NavigationDrawerItem {
  ///当该项目被选中时要显示的页面
  final Widget page;

  /// 包含图标、标签等
  final NavigationDrawerDestination destination;

  ///
  /// 创建一个导航抽屉项目
  ///
  /// 必须提供 [page] 和 [destination]
  ///
  const NavigationDrawerItem({required this.page, required this.destination});
}
