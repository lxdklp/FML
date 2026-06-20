import 'java_info.dart';

class JavaRuntime {
  final JavaInfo info;
  final String executable;
  final bool isJdk;

  JavaRuntime({
    required this.info,
    required this.executable,
    required this.isJdk,
  });

  Map<String, dynamic> toJson() => {
    'info': info.toJson(),
    'executable': executable,
    'isJdk': isJdk,
  };

  factory JavaRuntime.fromJson(Map<String, dynamic> json) => JavaRuntime(
    info: JavaInfo.fromJson(json['info'] as Map<String, dynamic>),
    executable: json['executable'] as String,
    isJdk: json['isJdk'] as bool,
  );

  @override
  String toString() => '${isJdk ? 'JDK' : 'JRE'} ${info.version} @ $executable';
}
