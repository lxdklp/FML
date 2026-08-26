import 'package:material_ui/material_ui.dart';

class DownloadModpackPage extends StatefulWidget {
  const DownloadModpackPage({
    super.key,
    required this.gameName,
    required this.downloadUrl,
  });

  final String gameName;
  final String downloadUrl;

  @override
  DownloadModpackPageState createState() => DownloadModpackPageState();
}

class DownloadModpackPageState extends State<DownloadModpackPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
      ),
      body: Center(
        child: Text('游戏名称: ${widget.gameName}, 下载地址: ${widget.downloadUrl}'),
      ),
    );
  }
}