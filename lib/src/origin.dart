library linkcheck.source;

import 'package:source_span/source_span.dart';

/// Origin of a link. Contains information about the exact place in a file
/// (URI) and some additional helpful info.
class Origin {
  final Uri uri;
  final SourceSpan span;
  final String tagName;
  final String text;
  final String outerHtml;

  Origin(this.uri, this.span, this.tagName, this.text, this.outerHtml);

  Origin.fromMap(Map<String, Object> map)
      : this(
            Uri.parse(map["uri"] as String),
            _deserializeSpan(map["span"] as Map<String, Object>),
            map["tagName"] as String,
            map["text"] as String,
            map["outerHtml"] as String);

  @override
  String toString() => "$uri (${span.start.line + 1}:${span.start.column})";

  Map<String, Object> toMap() => {
        "uri": uri.toString(),
        "span": _serializeSpan(span),
        "tagName": tagName,
        "text": text,
        "outerHtml": outerHtml
      };
}

Map<String, Object> _serializeSpan(SourceSpan span) => {
      "start": _serializeSourceLocation(span.start),
      "end": _serializeSourceLocation(span.end),
      "text": span.text
    };

SourceSpan _deserializeSpan(Map<String, Object> map) => SourceSpan(
    _deserializeSourceLocation(map["start"] as Map<String, Object>),
    _deserializeSourceLocation(map["end"] as Map<String, Object>),
    map["text"] as String);

Map<String, Object> _serializeSourceLocation(SourceLocation location) =>
    <String, Object>{
      "offset": location.offset,
      "line": location.line,
      "column": location.column,
      "sourceUrl": location.sourceUrl.toString()
    };

SourceLocation _deserializeSourceLocation(Map<String, Object> map) =>
    SourceLocation(map["offset"] as int,
        sourceUrl: Uri.parse(map["sourceUrl"] as String),
        line: map["line"] as int,
        column: map["column"] as int);
