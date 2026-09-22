import 'package:material_ui/material_ui.dart';
import 'package:fml/constants.dart';
import 'package:fml/function/github_proxy.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProxyPage extends StatefulWidget {
  const ProxyPage({super.key});

  @override
  ProxyPageState createState() => ProxyPageState();
}

class ProxyPageState extends State<ProxyPage> {
  final _customController = TextEditingController();
  SharedPreferences? _prefs;
  bool _enabled = true;
  bool _saving = false;
  String _selected = GithubProxy.prefixes.first;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _enabled = prefs.getBool(GithubProxy.enabledKey) ?? true;
        _selected = GithubProxy.selectedPrefix(prefs);
        _customController.text = prefs.getString(GithubProxy.customKey) ?? '';
      });
    } catch (_) {
      if (mounted) setState(() => _error = '读取设置失败，请重新打开此页面');
    }
  }

  Future<void> _save(Future<bool> Function() write) async {
    setState(() => _saving = true);
    try {
      if (!await write()) throw StateError('保存失败');
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存设置失败，请重试')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveCustom() async {
    final prefix = GithubProxy.normalizePrefix(_customController.text);
    if (prefix == null) {
      setState(() => _error = '请输入有效的 HTTP(S) 前缀，不含账号、查询参数或片段');
      return;
    }
    setState(() => _error = null);
    await _save(() => _prefs!.setString(GithubProxy.customKey, prefix));
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  Widget _settingsCard({required Widget child}) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _prefs != null && !_saving;
    final theme = Theme.of(context);
    final dropdown = DropdownButton<String>(
      isExpanded: true,
      value: _selected,
      underline: const SizedBox.shrink(),
      items: [
        for (final prefix in GithubProxy.prefixes)
          DropdownMenuItem(
            value: prefix,
            child: Text(prefix, overflow: TextOverflow.ellipsis),
          ),
        const DropdownMenuItem(value: GithubProxy.custom, child: Text('自定义')),
      ],
      onChanged: ready && _enabled
          ? (value) {
              if (value != null) {
                _save(() => _prefs!.setString(GithubProxy.prefixKey, value));
              }
            }
          : null,
    );
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: kDefaultPadding),
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: kDefaultPadding / 2,
            top: kDefaultPadding,
            bottom: kDefaultPadding,
          ),
          child: Text('GitHub 加速', style: theme.textTheme.headlineMedium),
        ),
        _settingsCard(
          child: SwitchListTile(
            title: const Text('启用下载加速'),
            subtitle: const Text('用于加速 GitHub 资源下载'),
            value: _enabled,
            onChanged: ready
                ? (value) => _save(
                    () => _prefs!.setBool(GithubProxy.enabledKey, value),
                  )
                : null,
          ),
        ),
        if (_enabled) ...[
          _settingsCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kDefaultPadding,
                vertical: kDefaultPadding / 2,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final label = Text('加速地址', style: theme.textTheme.bodyLarge);
                  if (constraints.maxWidth < 420) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [label, dropdown],
                    );
                  }
                  return Row(
                    children: [
                      label,
                      const Spacer(),
                      SizedBox(width: 300, child: dropdown),
                    ],
                  );
                },
              ),
            ),
          ),
          if (_selected == GithubProxy.custom)
            _settingsCard(
              child: Padding(
                padding: const EdgeInsets.all(kDefaultPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('自定义加速地址', style: theme.textTheme.bodyLarge),
                    const SizedBox(height: kDefaultPadding),
                    TextField(
                      controller: _customController,
                      enabled: ready,
                      decoration: InputDecoration(
                        hintText: 'https://example.com/',
                        errorText: _error,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _saveCustom(),
                    ),
                    const SizedBox(height: kDefaultPadding),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: ready ? _saveCustom : null,
                        child: const Text('保存自定义加速地址'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}
