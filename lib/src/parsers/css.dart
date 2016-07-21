library linkcheck.parsers.css;

import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart';
import 'package:source_span/source_span.dart';

import '../worker/fetch_results.dart';
import '../destination.dart';
import '../link.dart';
import '../origin.dart';

FetchResults parseCss(
    String content, Destination current, DestinationResult checked) {
  var style = css.parse(content);
  var urlHarvester = new CssUrlHarvester();
  style.visit(urlHarvester);

  var links = new List<Link>();
  var currentDestinations = new List<Destination>();
  for (var reference in urlHarvester.references) {
    var origin = new Origin(current.finalUri, reference.span, "url",
        reference.url, "url(\"${reference.url}\")");

    // Valid URLs can be surrounded by spaces.
    var url = reference.url.trim();
    Link link;

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
