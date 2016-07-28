library linkcheck.parsers.html;

import 'package:html/dom.dart';
import 'package:html/parser.dart';

import '../destination.dart';
import '../link.dart';
import '../origin.dart';
import '../worker/fetch_results.dart';

/// Takes a DOM element and extracts a link from it.
///
/// The provided [attributes] will be checked in sequence.
///
/// Setting [parseable] to true will create a link to a destination with
/// [Destination.isSource] set to `true`. For example, links in <a href> are
/// often parseable (they are HTML), links in <img src> often aren't.
Link extractLink(Uri uri, Element element, final List<String> attributes,
    final List<Destination> destinations, bool parseable) {
  var origin = new Origin(uri, element.sourceSpan, element.localName,
      element.text, element.outerHtml);
  String reference;
  for (var attributeName in attributes) {
    reference = element.attributes[attributeName];
    if (reference != null) break;
  }
  if (reference == null) {
    throw new StateError("Element $element does not have any of the attributes "
        "$attributes");
  }

  // Valid URLs can be surrounded by spaces.
  reference = reference.trim();
  Uri destinationUri;
  try {
    destinationUri = uri.resolve(reference);
  } on FormatException {
    Destination destination = new Destination.invalid(reference);
    return new Link(origin, destination, null);
  }
  var destinationUrlNaked = destinationUri.removeFragment().toString();

  for (var existing in destinations) {
    if (destinationUrlNaked == existing.url) {
      return new Link(origin, existing, destinationUri.fragment);
    }
  }

  Destination destination = new Destination(destinationUri);
  destination.isSource = parseable;
  destinations.add(destination);
  return new Link(origin, destination, destinationUri.fragment);
}

FetchResults parseHtml(String content, Uri uri, Destination current,
    DestinationResult checked, bool ignoreLinks) {
  var doc = parse(content, generateSpans: true, sourceUrl: uri.toString());

  // Find parseable destinations
  // TODO: add the following: meta refreshes, forms, metadata
  //   `<meta http-equiv="refresh" content="5; url=redirect.html">`
  // TODO: work with http://www.w3schools.com/tags/tag_base.asp (can be anywhere) (<base href="..">)
  // TODO: get <meta> robot directives - https://github.com/stevenvachon/broken-link-checker/blob/master/lib/internal/scrapeHtml.js#L164

  var anchors = doc
      .querySelectorAll("body [id], body [name]")
      .map((element) => element.attributes["id"] ?? element.attributes["name"])
      .toList();
  checked.anchors = anchors;

  if (ignoreLinks) {
    checked.wasParsed = true;
    return new FetchResults(checked, const []);
  }

  Uri baseUri = current.finalUri;
  var baseElements = doc.querySelectorAll("base[href]");
  if (baseElements.isNotEmpty) {
    // More than one base element per page is not according to HTML specs.
    // At the moment, we just ignore that. But TODO: solve for pages with more
    baseUri = baseUri.resolve(baseElements.first.attributes["href"]);
  }

  var linkElements = doc.querySelectorAll(
      "a[href], area[href], iframe[src], link[rel='stylesheet']");

  List<Destination> currentDestinations = <Destination>[];

  /// TODO: add destinations to queue, but NOT as a side effect inside extractLink
  List<Link> links = linkElements
      .map((element) => extractLink(baseUri, element,
          const ["href", "src"], currentDestinations, true))
      .toList();

  // Find resources
  var resourceElements =
      doc.querySelectorAll("link[href], [src], object[data]");
  Iterable<Link> currentResourceLinks = resourceElements.map((element) =>
      extractLink(baseUri, element, const ["src", "href", "data"],
          currentDestinations, false));

  links.addAll(currentResourceLinks);

  // TODO: add srcset extractor (will create multiple links per element)

  checked.wasParsed = true;
  return new FetchResults(checked, links);
}
