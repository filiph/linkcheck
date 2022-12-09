import 'package:meta/meta.dart';
import 'package:source_span/source_span.dart';

/// Origin of a link. Contains information about the exact place in a file
/// (URI) and some additional helpful info.
@immutable
class Origin {
  final Uri uri;
  final SourceSpan span;
  final String tagName;
  final String text;
  final String outerHtml;

  Origin(this.uri, this.span, this.tagName, this.text, this.outerHtml);

  @override
  String toString() => '$uri (${span.start.line + 1}:${span.start.column})';
}
