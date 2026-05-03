class JavaInfo {
  final String version;
  final String? vendor;
  final String path;
  final String os;
  final String arch;

  JavaInfo({
    required this.version,
    this.vendor,
    required this.path,
    required this.os,
    required this.arch,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'vendor': vendor,
    'path': path,
    'os': os,
    'arch': arch,
  };

  factory JavaInfo.fromJson(Map<String, dynamic> json) => JavaInfo(
    version: json['version'] as String,
    vendor: json['vendor'] as String?,
    path: json['path'] as String,
    os: json['os'] as String,
    arch: json['arch'] as String,
  );

  @override
  String toString() => '$version (${vendor ?? 'Unknown'}) @ $path';
}
