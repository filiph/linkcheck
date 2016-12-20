library linkcheck.parsers.css;

import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart';
import 'package:source_span/source_span.dart';

import '../worker/fetch_results.dart';
import '../destination.dart';
import '../link.dart';
import '../origin.dart';
import 'package:csslib/src/messages.dart';
import 'package:logging/logging.dart';

FetchResults parseCss(
    String content, Destination current, DestinationResult checked) {
  var urlHarvester = new CssUrlHarvester();
  int start = 0;
  bool foundError;
  do {
    // When CSS has fatal errors, move just after the last one and try to
    // parse the rest of the document. Otherwise we'd be ignoring URLs
    // just because CSS isn't valid.
    foundError = false;
    List<Message> errors = new List();
    if (start > 0) {
      start = content.indexOf("}", start);
      if (start < content.length - 1) start += 1;
    }
    var style = css.parse(content.substring(start), errors: errors);
    style.visit(urlHarvester);
    int offset = 0;
    errors.forEach((error) {
      if (error.level == Level.SEVERE) {
        offset = error.span.end.offset;
        foundError = true;
      }
    });
    start += offset;
  } while (foundError);

  var links = new List<Link>();
  var currentDestinations = new List<Destination>();
  for (var reference in urlHarvester.references) {
    var origin = new Origin(current.finalUri, reference.span, "url",
        reference.url, "url(\"${reference.url}\")");

    // Valid URLs can be surrounded by spaces.
    var url = reference.url.trim();
    Link link;

    // Deal with unsupported schemes such as `telnet:` or `mailto:`.
    if (!checkSchemeSupported(url, current.finalUri)) {
      Destination destination = new Destination.unsupported(url);
      link = new Link(origin, destination, null);
      links.add(link);
      continue;
    }

    Uri destinationUri;
    try {
      destinationUri = current.finalUri.resolve(url);
    } on FormatException {
      Destination destination = new Destination.invalid(url);
      link = new Link(origin, destination, null);
      links.add(link);
      continue;
    }

    for (var existing in currentDestinations) {
      if (destinationUri == existing.uri) {
        link = new Link(origin, existing, null);
        break;
      }
    }

    if (link != null) {
      links.add(link);
      continue;
    }

    Destination destination = new Destination(destinationUri);
    currentDestinations.add(destination);
    link = new Link(origin, destination, null);
    links.add(link);
  }

  checked.wasParsed = true;
  return new FetchResults(checked, links);
}

class CssReference {
  SourceSpan span;
  String url;
  CssReference(this.span, this.url);
}

class CssUrlHarvester extends Visitor {
  List<CssReference> references = new List<CssReference>();

  @override
  void visitUriTerm(UriTerm node) {
    references.add(new CssReference(node.span, node.text));
  }
}
