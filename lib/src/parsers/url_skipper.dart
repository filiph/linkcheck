const _commentStart = '#';

const _commentStartEscape = r'\#';

/// Parses and keeps record of the URL patterns to skip.
class UrlSkipper {
  /// Path of the provided file with regexps to skip.
  final String? path;

  final List<_UrlSkipperRecord> _records;

  UrlSkipper(this.path, Iterable<String> lines)
      : _records = _parse(lines).toList(growable: false);

  UrlSkipper.empty()
      : path = null,
        _records = const [];

  bool skips(String url) => _records.any((record) => record.skips(url));

  @override
  String toString() {
    final patterns = _records.map((rec) => rec.pattern.pattern).join(', ');
    return 'UrlSkipper<$patterns>';
  }

  String explain(String url) {
    final records = _records.where((record) => record.skips(url));
    if (records.isEmpty) {
      throw ArgumentError('Url $url was passed to explain() but there '
          'is no record that skips it.');
    }
    final list = records
        .map((rec) => '${rec.pattern.pattern} (line ${rec.line})')
        .join(', ');
    return "URL '$url' skipped because it was matched by the following "
        "regular expressions of skip file '$path': $list";
  }

  static Iterable<_UrlSkipperRecord> _parse(Iterable<String> lines) sync* {
    var lineNumber = 1;
    for (var line in lines) {
      line = line.trim();

      if (line.startsWith(_commentStart) || line.isEmpty) {
        lineNumber += 1;
        continue;
      }
      if (line.startsWith(_commentStartEscape)) {
        line = line.substring(1);
      }

      yield _UrlSkipperRecord(lineNumber, line);
      lineNumber += 1;
    }
  }
}

class _UrlSkipperRecord {
  final int line;

  final RegExp pattern;

  _UrlSkipperRecord(this.line, String pattern) : pattern = RegExp(pattern);

  bool skips(String url) => pattern.hasMatch(url);
}
