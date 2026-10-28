class MavenVersionRange {
  MavenVersionRange(String value) : _ranges = _parse(value.trim());

  final List<_Range> _ranges;

  bool contains(String version) =>
      _ranges.any((range) => range.contains(version));

  static List<_Range> _parse(String value) {
    if (value.isEmpty) throw const FormatException('版本范围不能为空');
    if (!value.startsWith('[') && !value.startsWith('(')) {
      if (RegExp(r'[\s,\[\]()]').hasMatch(value)) {
        throw const FormatException('无效的 Maven 版本范围');
      }
      return [const _Range(null, null, false, false)];
    }
    final ranges = <_Range>[];
    var remaining = value;
    while (remaining.isNotEmpty) {
      final match = RegExp(r'^([\[(])([^\[\]()]*)([\])])')
          .firstMatch(remaining);
      if (match == null) throw const FormatException('无效的 Maven 版本范围');
      final bounds = match[2]!.split(',').map((v) => v.trim()).toList();
      final includeLower = match[1] == '[';
      final includeUpper = match[3] == ']';
      String? lower;
      String? upper;
      if (bounds.length == 1 &&
          includeLower &&
          includeUpper &&
          bounds[0].isNotEmpty) {
        lower = upper = bounds[0];
      } else if (bounds.length == 2) {
        lower = bounds[0].isEmpty ? null : bounds[0];
        upper = bounds[1].isEmpty ? null : bounds[1];
        if ((lower == null && includeLower) ||
            (upper == null && includeUpper)) {
          throw const FormatException('无界端点必须使用圆括号');
        }
      } else {
        throw const FormatException('无效的 Maven 版本范围');
      }
      if ([lower, upper].any((v) => v != null && RegExp(r'\s').hasMatch(v))) {
        throw const FormatException('版本号不能包含空白字符');
      }
      if (lower != null && upper != null) {
        final order = compareMavenVersions(lower, upper);
        if (order > 0 || (order == 0 && !(includeLower && includeUpper))) {
          throw const FormatException('版本范围的下界必须小于上界');
        }
      }
      if (ranges.isNotEmpty) {
        final previous = ranges.last;
        if (previous.upper == null ||
            lower == null ||
            compareMavenVersions(previous.upper!, lower) > 0) {
          throw const FormatException('版本范围不能重叠或逆序');
        }
      }
      ranges.add(_Range(lower, upper, includeLower, includeUpper));
      remaining = remaining.substring(match.end).trim();
      if (remaining.isNotEmpty) {
        if (!remaining.startsWith(',')) {
          throw const FormatException('版本范围之间缺少逗号');
        }
        remaining = remaining.substring(1).trim();
        if (remaining.isEmpty) throw const FormatException('版本范围不完整');
      }
    }
    return ranges;
  }
}

class _Range {
  const _Range(this.lower, this.upper, this.includeLower, this.includeUpper);
  final String? lower;
  final String? upper;
  final bool includeLower;
  final bool includeUpper;

  bool contains(String version) {
    final low = lower == null ? 1 : compareMavenVersions(version, lower!);
    final high = upper == null ? -1 : compareMavenVersions(version, upper!);
    return (low > 0 || (low == 0 && includeLower)) &&
        (high < 0 || (high == 0 && includeUpper));
  }
}

int compareMavenVersions(String left, String right) =>
    _compare(_versionItems(left), _versionItems(right));

List<Object> _versionItems(String value) {
  if (value.length > 1024) throw const FormatException('版本号过长');
  final version = value.toLowerCase();
  final root = <Object>[];
  var current = root;
  final groups = [root];
  var start = 0;
  var numeric = false;
  void group() {
    final child = <Object>[];
    current.add(child);
    groups.add(child);
    current = child;
  }

  Object item(String value, bool numeric, {bool followedByDigit = false}) {
    if (numeric) return BigInt.parse(value);
    if (followedByDigit) {
      value =
          const {'a': 'alpha', 'b': 'beta', 'm': 'milestone'}[value] ?? value;
    }
    return const {'ga': '', 'final': '', 'release': '', 'cr': 'rc'}[value] ??
        value;
  }

  for (var i = 0; i < version.length; i++) {
    final char = version[i];
    if (char == '.' || char == '-' || char == '_') {
      current.add(
        i == start ? BigInt.zero : item(version.substring(start, i), numeric),
      );
      start = i + 1;
      if (char != '.') group();
      continue;
    }
    final digit = char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57;
    if (digit != numeric && i > start) {
      if (digit && current.isNotEmpty) group();
      current.add(
        item(version.substring(start, i), numeric, followedByDigit: digit),
      );
      start = i;
      group();
    }
    numeric = digit;
  }
  if (start < version.length) {
    if (!numeric && current.isNotEmpty) group();
    current.add(item(version.substring(start), numeric));
  }
  for (final list in groups.reversed) {
    for (var i = list.length - 1; i >= 0; i--) {
      final entry = list[i];
      if (entry == BigInt.zero ||
          entry == '' ||
          (entry is List && entry.isEmpty)) {
        list.removeAt(i);
      } else if (entry is! List) {
        break;
      }
    }
  }
  return root;
}

const _qualifiers = ['alpha', 'beta', 'milestone', 'rc', 'snapshot', '', 'sp'];

int _compareQualifier(String a, String b) {
  final x = _qualifiers.indexOf(a);
  final y = _qualifiers.indexOf(b);
  if (x == -1 && y == -1) return a.compareTo(b);
  return (x == -1 ? _qualifiers.length : x).compareTo(
    y == -1 ? _qualifiers.length : y,
  );
}

int _compare(Object? a, Object? b) {
  if (a == null) return b == null ? 0 : -_compare(b, null);
  if (a is BigInt) {
    if (b == null) return a.compareTo(BigInt.zero);
    return b is BigInt ? a.compareTo(b) : 1;
  }
  if (a is String) {
    if (b == null) return _compareQualifier(a, '');
    return b is String ? _compareQualifier(a, b) : -1;
  }
  final left = a as List<Object>;
  if (b is BigInt) return -1;
  if (b is String) return 1;
  final right = b as List<Object>? ?? const <Object>[];
  for (var i = 0; i < left.length || i < right.length; i++) {
    final result = _compare(
      i < left.length ? left[i] : null,
      i < right.length ? right[i] : null,
    );
    if (result != 0) return result;
  }
  return 0;
}
