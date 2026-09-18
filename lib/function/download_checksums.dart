// 哈希处理
import 'download.dart';

class DownloadChecksums {
  final Map<String, Map<String, String>> _hashes = {};
  void addMetadata(dynamic value, {String Function(String)? rewriteUrl}) {
    if (value is List) {
      for (final child in value) {
        addMetadata(child, rewriteUrl: rewriteUrl);
      }
    } else if (value is Map) {
      final url = value['url'];
      if (url is String) {
        final hashes = <String, String>{
          for (final key in ['sha1', 'sha512'])
            if (value[key] is String && (value[key] as String).isNotEmpty)
              key: value[key],
        };
        if (hashes.isNotEmpty) {
          _hashes[url] = hashes;
          if (rewriteUrl != null) _hashes[rewriteUrl(url)] = hashes;
        }
      }
      for (final child in value.values) {
        addMetadata(child, rewriteUrl: rewriteUrl);
      }
    }
  }

  String? sha1For(String url) => _hashes[url]?['sha1'];
  String? sha512For(String url) => _hashes[url]?['sha512'];

  Map<String, String> task(String url, String path) => {
    'url': url,
    'path': path,
    ...?_hashes[url],
  };

  Future<bool> validFile(String path, String url) => DownloadUtils.validFile(
    path,
    sha1Hash: sha1For(url),
    sha512Hash: sha512For(url),
  );
}
