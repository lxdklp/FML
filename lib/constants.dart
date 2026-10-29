import 'dart:ui' show FontWeight;

///
/// 应用常量
///
const kAppName = 'Flutter Minecraft Launcher';
const kAppNameAbb = 'FML';
const kDefaultPadding = 16.0;

///
/// API KEY
///
const String kCurseforgeApiKey = r'$2a$10$2nu.vP1qQjDgInxe1xsyzuxR73iqaJ23TzFshO4Z0yRfS93d1gDTm';
const String kMicrosoftClientId = r'3847de77-c7ca-4daa-a0b7-50850446d58c';

///
/// 启动时获取的常量
///
late final String gAppVersion;
late final int gAppBuildNumber;
late final String gAppDefaultUserAgent;
late final String gAppModrinthUserAgent;

///
/// 字体字重
///
class AppFontWeights {
  static const FontWeight body = FontWeight.w500; // 正文
  static const FontWeight label = FontWeight.w500; // 标签/按钮
  static const FontWeight title = FontWeight.w700; // 标题
  static const FontWeight headline = FontWeight.w800; // 更大标题
}

///
/// URLs
///
class AppUrls {
  static const String javaDownload =
      'https://www.oracle.com/cn/java/technologies/downloads/';
  static const String latestVersionApi =
      'https://api.lxdklp.top/v1/fml/get_version';
  static const String githubReleasesApi =
      'https://api.github.com/repos/lxdklp/FML/releases';
  static const String githubProject = 'https://github.com/lxdklp/FML';
  static const String githubLatestRelease =
      '${AppUrls.githubProject}/releases/latest';
  static const String officialWebsite = 'https://fml.lxdklp.top';
}

//
// 路由
//
const String kOnlineOwnerRoute = '/online/owner';
const String kNativeMethodChannel = 'lxdklp/fml_native';
