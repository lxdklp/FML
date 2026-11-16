import 'package:material_ui/material_ui.dart';
import 'package:fml/function/config/game_config_validator.dart';

Future<void> showGameConfigCheck(
  BuildContext context,
  GameConfigValidator validator,
  List<GameConfigIssue> issues,
) async {
  if (issues.isEmpty) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _GameConfigCheckDialog(validator: validator, issues: issues),
  );
}

class _GameConfigCheckDialog extends StatefulWidget {
  const _GameConfigCheckDialog({required this.validator, required this.issues});
  final GameConfigValidator validator;
  final List<GameConfigIssue> issues;
  @override
  State<_GameConfigCheckDialog> createState() => _GameConfigCheckDialogState();
}

class _GameConfigCheckDialogState extends State<_GameConfigCheckDialog> {
  final _selected = <GameConfigIssue>{};
  bool _saving = false;
  String? _error;

  Future<void> _remove() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.validator.removeMissing(_selected);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存配置失败: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('检查游戏配置'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '以下游戏目录或版本不存在，是否从配置文件中删除对应记录？此操作只修改 FML 配置，不会删除任何游戏文件。移动硬盘或网络目录暂时不可用时，可以保留记录。',
              ),
              const SizedBox(height: 12),
              for (final issue in widget.issues)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(issue.label),
                  subtitle: Text(
                    '${issue.reason}\n${issue.checkedPath.isEmpty ? '未配置路径' : issue.checkedPath}${issue.canRemove ? '' : '\n此项保留，不参与删除'}',
                  ),
                  value: _selected.contains(issue),
                  onChanged: !issue.canRemove || _saving
                      ? null
                      : (value) => setState(() {
                          if (value == true) {
                            _selected.add(issue);
                          } else {
                            _selected.remove(issue);
                          }
                        }),
                ),
              if (_saving) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('保留并继续'),
        ),
        TextButton(
          onPressed: _saving || _selected.isEmpty ? null : _remove,
          child: const Text('从配置中删除所选项'),
        ),
      ],
    ),
  );
}
