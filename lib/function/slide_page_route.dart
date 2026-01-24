import 'package:flutter/material.dart';

///一个通用的从右向左滑动的路由切换动画
class SlidePageRoute extends PageRouteBuilder {
  ///路由跳转的目标页面
  final Widget page;

  ///动画时值
  final Duration duration;

  ///
  ///[page] 必填，路由跳转的目标页面
  ///
  ///[duration] 动画时值，默认为300ms
  ///
  SlidePageRoute({
    required this.page,
    this.duration = const Duration(milliseconds: 300),
  }) : super(
         //传入动画时间
         transitionDuration: duration,
         reverseTransitionDuration: duration,
         pageBuilder: (context, animation, secondaryAnimation) => page,
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           //定义动画的开始和结束位置（相对窗口的位置）
           const begin = Offset(1.0, 0.0);
           const end = Offset.zero;
           const curve = Curves.ease;

           final tween = Tween(
             begin: begin,
             end: end,
           ).chain(CurveTween(curve: curve));

           //用Material包裹添加阴影效果
           return SlideTransition(
             position: animation.drive(tween),
             child: Material(elevation: 8, child: child),
           );
         },
       );
}
