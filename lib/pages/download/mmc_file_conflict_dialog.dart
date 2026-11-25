import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fml/function/mmc/mmc_install_service.dart';

Future<MmcFileConflictChoice?> showMmcFileConflictDialog(
  BuildContext context,
  MmcFileConflict conflict,
) => showDialog<MmcFileConflictChoice>(
  context: context,
  barrierDismissible: false,
  builder: (_) => MmcFileConflictDialog(conflict: conflict),
);

class MmcFileConflictDialog extends StatelessWidget {
  const MmcFileConflictDialog({super.key, required this.conflict});

  final MmcFileConflict conflict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).vertical -
        32;
    void close([MmcFileConflictChoice? choice]) =>
        Navigator.pop(context, choice);

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          child: SizedBox(
            width: 1080,
            height: math.min(760, availableHeight),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 620;
                  final existing = _FilePreview(
                    title: '先前文件',
                    file: conflict.existing,
                  );
                  final incoming = _FilePreview(
                    title: '当前文件',
                    file: conflict.incoming,
                  );
                  final choices = [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => close(MmcFileConflictChoice.existing),
                        child: const Text('保留先前文件'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => close(MmcFileConflictChoice.incoming),
                        child: const Text('保留当前文件'),
                      ),
                    ),
                  ];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('选择要保留的文件', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 8),
                      const Text('这两个文件会写入同一位置, 请选择要保留的一份。'),
                      const SizedBox(height: 8),
                      Text(
                        conflict.identical
                            ? '两份文件内容一致, 将保留所选文件名。'
                            : '两份文件内容不同, 请对比后选择。',
                        style: TextStyle(color: theme.colorScheme.primary),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, previewConstraints) {
                            if (narrow || previewConstraints.maxHeight < 240) {
                              final height = math.max(
                                220.0,
                                (previewConstraints.maxHeight - 12) / 2,
                              );
                              return SingleChildScrollView(
                                child: Column(
                                  children: [
                                    SizedBox(height: height, child: existing),
                                    const SizedBox(height: 12),
                                    SizedBox(height: height, child: incoming),
                                  ],
                                ),
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: existing),
                                const SizedBox(width: 12),
                                Expanded(child: incoming),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (narrow) ...[
                        Row(children: choices),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: close,
                            child: const Text('取消导入'),
                          ),
                        ),
                      ] else
                        Row(
                          children: [
                            TextButton(
                              onPressed: close,
                              child: const Text('取消导入'),
                            ),
                            const Spacer(),
                            SizedBox(width: 360, child: Row(children: choices)),
                          ],
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilePreview extends StatelessWidget {
  const _FilePreview({required this.title, required this.file});

  final String title;
  final MmcConflictFile file;

  // 截断恰好落在 UTF-8 字符中间时, 解码器暂存不完整的尾部.
  String? _text() {
    final bytes = file.preview;
    final truncated = file.size > bytes.length;
    try {
      final String decoded;
      if (truncated) {
        final buffer = StringBuffer();
        final decoder = utf8.decoder.startChunkedConversion(
          StringConversionSink.fromStringSink(buffer),
        );
        decoder.add(bytes);
        decoded = buffer.toString();
      } else {
        decoded = utf8.decode(bytes);
      }
      if (decoded.runes.any(
        (value) =>
            (value < 32 && value != 9 && value != 10 && value != 13) ||
            value == 127,
      )) {
        return null;
      }
      return decoded;
    } on FormatException {
      // 其他编码和二进制内容使用十六进制预览.
      return null;
    }
  }

  String _hex(int length) {
    final rows = <String>[];
    for (var offset = 0; offset < length; offset += 16) {
      final bytes = file.preview.sublist(offset, math.min(offset + 16, length));
      rows.add(
        '${offset.toRadixString(16).padLeft(6, '0')}  '
        '${bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );
    }
    return rows.join('\n');
  }

  String get _size {
    final size = file.size;
    if (size < 1024) return '$size B';
    final unit = size < 1024 * 1024 ? 'KiB' : 'MiB';
    final divisor = unit == 'KiB' ? 1024 : 1024 * 1024;
    return '${(size / divisor).toStringAsFixed(1)} $unit ($size B)';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _text();
    final isText = text != null;
    final displayedBytes = isText
        ? file.preview.length
        : math.min(512, file.preview.length);
    final truncated = file.size > displayedBytes;
    final preview = isText ? text : _hex(displayedBytes);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('$title · $_size', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 54),
              child: SingleChildScrollView(
                child: SelectableText(file.relativePath),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${isText ? '文本预览' : '非 UTF-8 文本或二进制文件 · 十六进制预览'}'
              '${truncated ? ' · 仅显示前 $displayedBytes B' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ColoredBox(
                color: theme.colorScheme.surfaceContainerLow,
                child: SizedBox.expand(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(
                        preview.isEmpty ? '(空文件)' : preview,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
