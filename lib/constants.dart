///
/// 应用常量
///
const kAppName = 'Flutter Minecraft Launcher';
const kAppNameAbb = 'FML';
const kDefaultPadding = 16.0;

///
/// 启动时获取的常量
///
late final String gAppVersion;
late final String gAppUserAgent;
late final int gAppBuildNumber;

///
/// 字体字重
///
class AppFontWeights {
  static const double bodyWght = 520; // 正文
  static const double labelWght = 520; // 标签/按钮
  static const double titleWght = 700; // 标题
  static const double headlineWght = 850; // 更大标题
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
