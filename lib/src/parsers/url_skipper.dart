library linkcheck.parsers.url_skipper;

const _commentStart = "#";

const _commentStartEscape = r"\#";

/// Parses and keeps record of the URL patterns to skip.
class UrlSkipper {
  /// Path of the provided file with regexps to skip.
  final String path;

  final List<_UrlSkipperRecord> _records;

  UrlSkipper(this.path, Iterable<String> lines)
      : _records = _parse(lines).toList(growable: false);

  UrlSkipper.empty()
      : path = null,
        _records = const [];

  bool skips(String url) => _records.any((record) => record.skips(url));

  String toString() {
    var patterns = _records.map((rec) => rec.pattern.pattern).join(", ");
    return "UrlSkipper<$patterns>";
  }

  String explain(String url) {
    var records = _records.where((record) => record.skips(url));
    if (records.isEmpty) {
      throw new ArgumentError("Url $url was passed to explain() but there "
          "is no record that skips it.");
    }
    var list = records
        .map((rec) => "${rec.pattern.pattern} (line ${rec.line})")
        .join(", ");
    return "URL '$url' skipped because it was matched by the following "
        "regular expressions of skip file '$path': $list";
  }

  static Iterable<_UrlSkipperRecord> _parse(Iterable<String> lines) sync* {
    int lineNumber = 1;
    for (var line in lines) {
      line = line.trim();

      if (line.startsWith(_commentStart) || line.isEmpty) {
        lineNumber += 1;
        continue;
      }
      if (line.startsWith(_commentStartEscape)) {
        line = line.substring(1);
      }

      yield new _UrlSkipperRecord(lineNumber, line);
      lineNumber += 1;
    }
  }
}

class _UrlSkipperRecord {
  final int line;

  final RegExp pattern;

  _UrlSkipperRecord(this.line, String pattern)
      : this.pattern = new RegExp(pattern);

  bool skips(String url) => pattern.hasMatch(url);
}
