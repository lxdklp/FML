import 'package:material_ui/material_ui.dart';
import 'package:fml/function/java/java_launch_check.dart';

Future<bool> confirmJavaLaunch(
  BuildContext context,
  JavaLaunchCheck check,
) async {
  if (!check.needsWarning) return true;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Java 版本警告'),
          scrollable: true,
          content: Text(check.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('仍然启动'),
            ),
          ],
        ),
      ) ??
      false;
}
