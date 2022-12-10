import 'package:csslib/parser.dart' as css;
import 'package:csslib/parser.dart';
import 'package:csslib/visitor.dart';
import 'package:source_span/source_span.dart';

import '../destination.dart';
import '../link.dart';
import '../origin.dart';
import '../worker/fetch_results.dart';

FetchResults parseCss(
    String content, Destination current, DestinationResult checked) {
  var urlHarvester = CssUrlHarvester();
  int start = 0;
  bool foundError;
  do {
    // When CSS has fatal errors, move just after the last one and try to
    // parse the rest of the document. Otherwise we'd be ignoring URLs
    // just because CSS isn't valid.
    foundError = false;
    List<Message> errors = [];
    if (start > 0) {
      start = content.indexOf("}", start);
      if (start < content.length - 1) start += 1;
    }
    var style = css.parse(content.substring(start), errors: errors);
    style.visit(urlHarvester);
    var offset = 0;
    for (var error in errors) {
      if (error.level == MessageLevel.severe) {
        var errorSpan = error.span;
        if (errorSpan != null) {
          offset = errorSpan.end.offset;
          foundError = true;
        }
      }
    }
    start += offset;
  } while (foundError);

  var links = <Link>[];
  var currentDestinations = <Destination>[];
  for (var reference in urlHarvester.references) {
    var origin = Origin(current.finalUri, reference.span, "url", reference.url,
        "url(\"${reference.url}\")");

    // Valid URLs can be surrounded by spaces.
    var url = reference.url.trim();
    Link? link;

    // Deal with unsupported schemes such as `telnet:` or `mailto:`.
    if (!checkSchemeSupported(url, current.finalUri)) {
      Destination destination = Destination.unsupported(url);
      link = Link(origin, destination, null);
      links.add(link);
      continue;
    }

    Uri destinationUri;
    try {
      destinationUri = current.finalUri.resolve(url);
    } on FormatException {
      Destination destination = Destination.invalid(url);
      link = Link(origin, destination, null);
      links.add(link);
      continue;
    }

    for (var existing in currentDestinations) {
      if (destinationUri == existing.uri) {
        link = Link(origin, existing, null);
        break;
      }
    }

    if (link != null) {
      links.add(link);
      continue;
    }

    var destination = Destination(destinationUri);
    currentDestinations.add(destination);
    link = Link(origin, destination, null);
    links.add(link);
  }

  checked.wasParsed = true;
  return FetchResults(checked, links);
}

class CssReference {
  final SourceSpan span;
  final String url;

  CssReference(this.span, this.url);
}

class CssUrlHarvester extends Visitor {
  final List<CssReference> references = <CssReference>[];

  @override
  void visitUriTerm(UriTerm node) {
    var span = node.span;
    if (span != null) {
      references.add(CssReference(span, node.text));
    }
  }
}
