import 'package:shared_preferences/shared_preferences.dart';

class GithubProxy {
  static const enabledKey = 'githubProxyEnabled';
  static const prefixKey = 'githubProxyPrefix';
  static const customKey = 'githubProxyCustomPrefix';
  static const custom = 'custom';
  static const prefixes = [
    'https://gh-proxy.org/',
    'https://v4.gh-proxy.org/',
    'https://v6.gh-proxy.org/',
    'https://cdn.gh-proxy.org/',
    'https://axisnow.gh-proxy.org/',
  ];

  static String? normalizePrefix(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        RegExp(r'\s').hasMatch(trimmed)) {
      return null;
    }
    return '${trimmed.replaceFirst(RegExp(r'/+$'), '')}/';
  }

  static String selectedPrefix(SharedPreferences prefs) {
    final selected = prefs.getString(prefixKey);
    return selected == custom || prefixes.contains(selected)
        ? selected!
        : prefixes.first;
  }

  static String downloadUrl(String url, SharedPreferences prefs) {
    if (url.isEmpty || !(prefs.getBool(enabledKey) ?? true)) return url;
    final selected = selectedPrefix(prefs);
    final prefix = selected == custom
        ? normalizePrefix(prefs.getString(customKey) ?? '')
        : selected;
    return prefix == null ? url : '$prefix$url';
  }
}
