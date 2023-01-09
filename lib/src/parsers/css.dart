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
  final urlHarvester = CssUrlHarvester();
  var startIndex = 0;
  bool foundError;
  do {
    // When CSS has fatal errors, move just after the last one and try to
    // parse the rest of the document. Otherwise we'd be ignoring URLs
    // just because CSS isn't valid.
    foundError = false;
    final errors = <Message>[];
    if (startIndex > 0) {
      startIndex = content.indexOf('}', startIndex);
      if (startIndex < content.length - 1) startIndex += 1;
    }
    final style = css.parse(content.substring(startIndex), errors: errors);
    style.visit(urlHarvester);
    var offset = 0;
    for (final error in errors) {
      if (error.level == MessageLevel.severe) {
        final errorSpan = error.span;
        if (errorSpan != null) {
          offset = errorSpan.end.offset;
          foundError = true;
        }
      }
    }
    startIndex += offset;
  } while (foundError);

  final links = <Link>[];
  final currentDestinations = <Destination>[];
  for (final reference in urlHarvester.references) {
    final origin = Origin(current.finalUri, reference.span, 'url',
        reference.url, 'url("${reference.url}")');

    // Valid URLs can be surrounded by spaces.
    final url = reference.url.trim();
    Link? link;

    // Deal with unsupported schemes such as `telnet:` or `mailto:`.
    if (!checkSchemeSupported(url, current.finalUri)) {
      final destination = Destination.unsupported(url);
      link = Link(origin, destination, null);
      links.add(link);
      continue;
    }

    Uri destinationUri;
    try {
      destinationUri = current.finalUri.resolve(url);
    } on FormatException {
      final destination = Destination.invalid(url);
      link = Link(origin, destination, null);
      links.add(link);
      continue;
    }

    for (final existing in currentDestinations) {
      if (destinationUri == existing.uri) {
        link = Link(origin, existing, null);
        break;
      }
    }

    if (link != null) {
      links.add(link);
      continue;
    }

    final destination = Destination(destinationUri);
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
    final span = node.span;
    if (span != null) {
      references.add(CssReference(span, node.text));
    }
  }
}
