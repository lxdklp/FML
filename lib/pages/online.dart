import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:fml/function/slide_page_route.dart';
import 'package:system_info2/system_info2.dart';
import 'package:archive/archive.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fml/function/log.dart';
import 'package:fml/function/download.dart';
import 'package:fml/pages/online/owner.dart';
import 'package:fml/pages/online/member.dart';

class OnlinePage extends StatefulWidget {
  const OnlinePage({super.key});

  @override
  OnlinePageState createState() => OnlinePageState();
}

class OnlinePageState extends State<OnlinePage> {
  bool _coreExists = false;
  bool _coredownloading = false;
  bool _coreExtracting = false;
  bool _coreUpdate = false;
  bool _macosError = false;
  double _downloadProgress = 0.0;
  String _appVersion = "1.0.0";
  String _coreVersion = "未知";
  final TextEditingController _serverController = TextEditingController();

  // 打开URL
  Future<void> _launchURL(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法打开链接: $url')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发生错误: $e')));
    }
  }

  // 检查核心是否存在
  Future<void> _checkCoreExists() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('SelectedPath') ?? '';
    final path = prefs.getString('Path_$name') ?? '';
    if (Platform.isWindows) {
      final File core = File(
        '$path${Platform.pathSeparator}easytier${Platform.pathSeparator}easytier-core.exe',
      );
      setState(() {
        _coreExists = core.existsSync();
      });
    } else {
      final File core = File(
        '$path${Platform.pathSeparator}easytier${Platform.pathSeparator}easytier-core',
      );
      setState(() {
        _coreExists = core.existsSync();
      });
    }
  }

  // 检测核心版本
  Future<void> _checkCoreVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('SelectedPath') ?? '';
    final path = prefs.getString('Path_$name') ?? '';
    final String core =
        ('$path${Platform.pathSeparator}easytier${Platform.pathSeparator}easytier-core');
    try {
      final ProcessResult proc = await Process.run(core, ['--version']);
      final String output =
          'v${proc.stdout.toString().trim().substring(14, proc.stdout.toString().trim().length - 9)}';
      setState(() {
        _coreVersion = output;
      });
    } catch (e) {
      setState(() {
        if (Platform.isMacOS) {
          _macosError = true;
        }
      });
      LogUtil.log('获取EasyTier核心版本失败: $e', level: 'ERROR');
      return;
    }
  }

  // 检查核心更新
  Future<void> _checkCoreUpdate() async {
    try {
      Dio dio = Dio();
      Options options = Options(
        headers: {'User-Agent': 'FML-App/$_appVersion'},
      );
      final response = await dio.get(
        'https://api.github.com/repos/EasyTier/EasyTier/releases',
        options: options,
      );
      if (response.statusCode == 200) {
        Map<String, dynamic> loaderData = response.data[0];
        String latestVersion = loaderData['tag_name'];
        if (latestVersion != _coreVersion) {
          LogUtil.log('检测到EasyTier核心新版本: $latestVersion', level: 'INFO');
          setState(() {
            _coreUpdate = true;
          });
        } else {
          LogUtil.log('EasyTier核心已是最新版本: $_coreVersion', level: 'INFO');
        }
      }
    } catch (e) {
      LogUtil.log('检查EasyTier核心更新失败: $e', level: 'ERROR');
      return;
    }
  }

  // 更新核心
  Future<void> _updateCore() async {
    setState(() {
      _coreExists = false;
      _coredownloading = true;
    });
    await _installCore();
    setState(() {
      _coreUpdate = false;
    });
  }

  // 读取App版本
  Future<void> _loadAppVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final version = prefs.getString('version') ?? "1.0.0";
    setState(() {
      _appVersion = version;
    });
  }

  // 系统不支持弹窗
  Future<void> _showUnsupportedDialog() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('不支持的系统'),
          content: Text(
            '平台: ${Platform.operatingSystem} 架构: ${SysInfo.kernelArchitecture.name}',
          ),
          actions: <Widget>[
            TextButton(
              child: Text('确定'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // 解压核心
  Future<void> _extractCore(String extractPath) async {
    String zipPath = '$extractPath${Platform.pathSeparator}easytier.zip';
    try {
      LogUtil.log('开始解压: $zipPath 到 $extractPath', level: 'INFO');
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        final filename = file.name;
        final bareFilename = filename.split('/').last;
        if (file.isFile && bareFilename.isNotEmpty) {
          final data = file.content as List<int>;
          final filePath = '$extractPath${Platform.pathSeparator}$bareFilename';
          File(filePath)
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
          // 在类Unix系统上设置可执行权限
          if (!Platform.isWindows) {
            await Process.run('chmod', ['+x', filePath]);
          }
        }
      }
      // 删除zip文件
      await File(zipPath).delete();
      LogUtil.log('解压完成', level: 'INFO');
      _checkCoreVersion();
      setState(() {
        _coreExists = true;
      });
    } catch (e) {
      LogUtil.log('解压失败: $e', level: 'ERROR');
      rethrow;
    }
  }

  // 获取系统架构
  String _getSystemArchitecture() {
    String arch = SysInfo.kernelArchitecture.name;
    if (arch == 'UNKNOWN') {
      if (Platform.isWindows) {
        final processorArchitecture =
            Platform.environment['PROCESSOR_ARCHITECTURE'];
        LogUtil.log(
          'PROCESSOR_ARCHITECTURE: $processorArchitecture',
          level: 'INFO',
        );
        if (processorArchitecture == 'AMD64' ||
            processorArchitecture == 'x64') {
          return 'X86_64';
        } else if (processorArchitecture == 'ARM64') {
          return 'ARM64';
        }
      }
      LogUtil.log('无法确定系统架构,使用默认值 X86_64', level: 'WARN');
      return 'X86_64';
    }
    return arch;
  }

  // 安装核心
  Future<void> _installCore() async {
    String downloadUrl = '';
    Dio dio = Dio();
    Options options = Options(headers: {'User-Agent': 'FML-App/$_appVersion'});
    try {
      final response = await dio.get(
        'https://api.github.com/repos/EasyTier/EasyTier/releases',
        options: options,
      );
      if (response.statusCode == 200) {
        Map<String, dynamic> loaderData = response.data[0];
        String architecture = _getSystemArchitecture();
        if (Platform.isMacOS) {
          if (architecture == 'X86_64') {
            LogUtil.log('为 macOS x86_64 下载', level: 'INFO');
            for (var asset in loaderData['assets']) {
              if (asset['name'].startsWith('easytier-macos-x86_64')) {
                LogUtil.log(
                  'Found asset: ${asset['name']} url: ${asset['browser_download_url']}',
                  level: 'INFO',
                );
                downloadUrl = asset['browser_download_url'];
              }
            }
          } else if (architecture == 'ARM64') {
            LogUtil.log('为 macOS arm64 下载', level: 'INFO');
            for (var asset in loaderData['assets']) {
              if (asset['name'].startsWith('easytier-macos-aarch64')) {
                LogUtil.log(
                  'Found asset: ${asset['name']} url: ${asset['browser_download_url']}',
                  level: 'INFO',
                );
                downloadUrl = asset['browser_download_url'];
              }
            }
          } else {
            LogUtil.log('不支持的 macOS 架构: $architecture', level: 'ERROR');
            _showUnsupportedDialog();
          }
        } else if (Platform.isWindows) {
          if (architecture == 'X86_64') {
            LogUtil.log('为 Windows x86_64 下载', level: 'INFO');
            for (var asset in loaderData['assets']) {
              if (asset['name'].startsWith('easytier-windows-x86_64')) {
                LogUtil.log(
                  'Found asset: ${asset['name']} url: ${asset['browser_download_url']}',
                  level: 'INFO',
                );
                downloadUrl = asset['browser_download_url'];
              }
            }
          } else if (architecture == 'ARM64') {
            LogUtil.log('为 Windows arm64 下载', level: 'INFO');
            for (var asset in loaderData['assets']) {
              if (asset['name'].startsWith('easytier-windows-arm64')) {
                LogUtil.log(
                  'Found asset: ${asset['name']} url: ${asset['browser_download_url']}',
                  level: 'INFO',
                );
                downloadUrl = asset['browser_download_url'];
              }
            }
          } else {
            LogUtil.log('不支持的 Windows 架构: $architecture', level: 'ERROR');
            _showUnsupportedDialog();
          }
        } else if (Platform.isLinux) {
          if (architecture == 'X86_64') {
            LogUtil.log('为 Linux x86_64 下载', level: 'INFO');
            for (var asset in loaderData['assets']) {
              if (asset['name'].startsWith('easytier-linux-x86_64')) {
                LogUtil.log(
                  'Found asset: ${asset['name']} url: ${asset['browser_download_url']}',
                  level: 'INFO',
                );
                downloadUrl = asset['browser_download_url'];
              }
            }
          } else if (architecture == 'ARM64') {
            LogUtil.log('为 Linux arm64 下载', level: 'INFO');
            for (var asset in loaderData['assets']) {
              if (asset['name'].startsWith('easytier-linux-aarch64')) {
                LogUtil.log(
                  'Found asset: ${asset['name']} url: ${asset['browser_download_url']}',
                  level: 'INFO',
                );
                downloadUrl = asset['browser_download_url'];
              }
            }
          } else {
            LogUtil.log('不支持的 Linux 架构: $architecture', level: 'ERROR');
            _showUnsupportedDialog();
          }
        } else {
          LogUtil.log('不支持的平台: ${Platform.operatingSystem}', level: 'ERROR');
          _showUnsupportedDialog();
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('获取Github API失败: $e')));
      return;
    }
    downloadUrl = 'https://edgeone.gh-proxy.org/$downloadUrl';
    LogUtil.log('开始下载: $downloadUrl', level: 'INFO');
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('SelectedPath') ?? '';
    final path = prefs.getString('Path_$name') ?? '';
    final Directory easytierDir = Directory(
      '$path${Platform.pathSeparator}easytier',
    );
    if (!await easytierDir.exists()) {
      await easytierDir.create(recursive: true);
    }
    setState(() {
      _coredownloading = true;
    });
    final String zipPath =
        '${easytierDir.path}${Platform.pathSeparator}easytier.zip';
    DownloadUtils.downloadFile(
      url: downloadUrl,
      savePath: zipPath,
      onProgress: (progress) {
        setState(() {
          _downloadProgress = progress;
        });
      },
      onSuccess: () {
        LogUtil.log('下载完成', level: 'INFO');
        _checkCoreExists();
        setState(() {
          _coreExtracting = true;
          _coredownloading = false;
        });
        _extractCore(easytierDir.path)
            .then((_) {
              setState(() {
                _coreExtracting = false;
              });
              _checkCoreExists();
              if (!mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('EasyTier核心安装完成')));
            })
            .catchError((e) {
              setState(() {
                _coreExtracting = false;
              });
              if (!mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('解压失败: $e')));
            });
      },
      onError: (error) {
        LogUtil.log('下载失败: $error', level: 'ERROR');
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('下载失败: $error')));
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _checkCoreExists();
    _loadAppVersion();
    _checkCoreVersion();
    _checkCoreUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ListView(
          children: [
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: const Text('支持与 FML、HMCL、PCL2-CE、FCL 客户端联机'),
                subtitle: const Text('基于p2p,使用Scaffolding协议通讯,联机效果取决于你的网络环境'),
                leading: const Icon(Icons.info),
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: const Text('关于EasyTier'),
                subtitle: const Text('一款简单、安全、去中心化的内网穿透和异地组网工具'),
                leading: const Icon(Icons.info),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _launchURL('https://easytier.cn/'),
              ),
            ),
            if (_coreExists) ...[
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: const Text('EasyTier 已安装'),
                  subtitle: _macosError
                      ? Text('请在 设置-隐私与安全-安全性 中授权 EasyTier')
                      : Text(
                          '当前版本: $_coreVersion ${_coreUpdate ? "有新版本可用" : "已为最新版本"}',
                        ),
                  leading: const Icon(Icons.check_circle),
                  trailing: _coreUpdate && !_macosError
                      ? IconButton(
                          icon: const Icon(Icons.update),
                          onPressed: () {
                            _updateCore();
                          },
                        )
                      : null,
                ),
              ),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        decoration: InputDecoration(
                          labelText: '打洞/中转 服务器地址',
                          hintText: '为了安全性与合规性,请仅使用自行部署的服务器',
                          prefixIcon: const Icon(Icons.dns),
                          border: const OutlineInputBorder(),
                        ),
                        controller: _serverController,
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: const Text('创建房间'),
                  subtitle: const Text('生成邀请码,与好友一起游玩'),
                  leading: const Icon(Icons.home),
                  onTap: () {
                    if (!_coreExists) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请先安装 EasyTier 核心')),
                      );
                      return;
                    }
                    if (_serverController.text.isEmpty &&
                        !OwnerPage.persistIsServerRunning) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请先输入打洞/中转服务器地址')),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      SlidePageRoute(
                        page: OwnerPage(
                          port: -1,
                          etServer: _serverController.text,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: const Text('加入房间'),
                  subtitle: const Text('输入邀请码,与好友一起游玩'),
                  leading: const Icon(Icons.login),
                  onTap: () {
                    if (!_coreExists) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请先安装 EasyTier 核心')),
                      );
                      return;
                    }
                    if (_serverController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请先输入打洞/中转服务器地址')),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      SlidePageRoute(
                        page: MemberPage(etServer: _serverController.text),
                      ),
                    );
                  },
                ),
              ),
            ] else ...[
              if (_coredownloading) ...[
                Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          title: const Text('EasyTier正在下载中...'),
                          subtitle: const Text(
                            '请稍候，下载完成后即可使用联机功能\nGitHub 加速由 gh-proxy.com 提供',
                          ),
                          leading: _coreExtracting
                              ? const CircularProgressIndicator()
                              : CircularProgressIndicator(),
                        ),
                        if (!_coreExtracting) ...[
                          LinearProgressIndicator(value: _downloadProgress),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_coreExtracting) ...[
                  Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: ListTile(
                      title: const Text('EasyTier正在解压中...'),
                      subtitle: const Text('请稍候，解压完成后即可使用联机功能'),
                      leading: const CircularProgressIndicator(),
                    ),
                  ),
                ],
              ] else ...[
                Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    title: const Text('EasyTier核心未安装'),
                    subtitle: const Text(
                      '请点击以通过GitHub自动安装EasyTier核心,请准备好相应的网络环境\n'
                      '仅支持macOS x86_64、macOS arm64、Windows x86_64、Windows arm64、Linux x86_64、Linux aarch64平台自动下载',
                    ),
                    leading: const Icon(Icons.error),
                    trailing: const Icon(Icons.download),
                    onTap: () => _installCore(),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
