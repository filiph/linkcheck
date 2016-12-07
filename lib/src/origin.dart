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
            Uri.parse(map["uri"]),
            _deserializeSpan(map["span"] as Map<String, Object>),
            map["tagName"],
            map["text"],
            map["outerHtml"]);

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

SourceSpan _deserializeSpan(Map<String, Object> map) => new SourceSpan(
    _deserializeSourceLocation(map["start"] as Map<String, Object>),
    _deserializeSourceLocation(map["end"] as Map<String, Object>),
    map["text"]);

Map<String, Object> _serializeSourceLocation(SourceLocation location) =>
    <String, Object>{
      "offset": location.offset,
      "line": location.line,
      "column": location.column,
      "sourceUrl": location.sourceUrl.toString()
    };

SourceLocation _deserializeSourceLocation(Map<String, Object> map) =>
    new SourceLocation(map["offset"],
        sourceUrl: Uri.parse(map["sourceUrl"]),
        line: map["line"],
        column: map["column"]);
