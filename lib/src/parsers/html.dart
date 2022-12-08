import 'dart:html';

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
/// [originUri] is the final URI of the document from which the link originates,
/// whereas [baseUri] is the same with applied `<base>` tag, if present.
///
/// Setting [parseable] to true will create a link to a destination with
/// [Destination.isSource] set to `true`. For example, links in <a href> are
/// often parseable (they are HTML), links in <img src> often aren't.
Link extractLink(Uri originUri, Uri baseUri, Element element,
    final List<String> attributes, final List<Destination> destinations,
    {bool parseable = false}) {
  var sourceSpan = element.sourceSpan;
  var localName = element.localName;

  if (sourceSpan == null || localName == null) {
    throw StateError(
        'Element $element is missing a ${#sourceSpan} or ${#localName}.');
  }

  var origin =
      Origin(originUri, sourceSpan, localName, element.text, element.outerHtml);
  String? reference;
  for (var attributeName in attributes) {
    reference = element.attributes[attributeName];
    if (reference != null) break;
  }
  if (reference == null) {
    throw StateError("Element $element does not have any of the attributes "
        "$attributes");
  }

  // Valid URLs can be surrounded by spaces.
  reference = reference.trim();

  // Deal with unsupported schemes such as `telnet:` or `mailto:`.
  if (!checkSchemeSupported(reference, baseUri)) {
    Destination destination = Destination.unsupported(reference);
    return Link(origin, destination, null);
  }

  Uri destinationUri;
  try {
    destinationUri = baseUri.resolve(reference);
  } on FormatException {
    Destination destination = Destination.invalid(reference);
    return Link(origin, destination, null);
  }
  var destinationUrlNaked = destinationUri.removeFragment().toString();

  for (var existing in destinations) {
    if (destinationUrlNaked == existing.url) {
      return Link(origin, existing, destinationUri.fragment);
    }
  }

  Destination destination = Destination(destinationUri);
  destination.isSource = parseable;
  destinations.add(destination);
  return Link(origin, destination, destinationUri.fragment);
}

/// Takes an anchor (`id` or `name` attribute of an HTML element, or
/// a fragment of a link) and normalizes it.
///
/// Anchors that can be percent-decoded, will. ("Hr%C3%A1%C4%8Dek" will
/// become "Hráček".) Others will be kept the same. ("Hráček" will stay
/// "Hráček".)
String normalizeAnchor(String anchor) {
  String decoded;
  try {
    decoded = Uri.decodeComponent(anchor);
  } on ArgumentError {
    // TODO: Report or handle ids and attributes that are not
    //       percent-decodable (they were not percent-encoded and they
    //       contain an invalid character.
    decoded = anchor;
  }
  return decoded;
}

FetchResults parseHtml(String content, Uri uri, Destination current,
    DestinationResult checked, bool ignoreLinks) {
  var doc = parse(content, generateSpans: true, sourceUrl: uri.toString());

  // Find parseable destinations
  // TODO: add the following: meta refreshes, forms, metadata
  //   `<meta http-equiv="refresh" content="5; url=redirect.html">`
  // TODO: get <meta> robot directives - https://github.com/stevenvachon/broken-link-checker/blob/master/lib/internal/scrapeHtml.js#L164

  var anchors = doc
      .querySelectorAll("body [id], body [name]")
      .map((element) => element.attributes["id"] ?? element.attributes["name"])
      .whereType<String>()
      .map(normalizeAnchor)
      .toList(growable: false);
  checked.anchors = anchors;

  if (ignoreLinks) {
    checked.wasParsed = true;
    return FetchResults(checked, const []);
  }

  Uri baseUri = current.finalUri;
  var baseElements = doc.querySelectorAll("base[href]");
  if (baseElements.isNotEmpty) {
    var firstBaseHref = (baseElements.first as BaseElement?)?.href;

    if (firstBaseHref != null) {
      // More than one base element per page is not according to HTML specs.
      // At the moment, we just ignore that. But TODO: solve for pages with more
      baseUri = baseUri.resolve(firstBaseHref);
    }
  }

  var linkElements = doc.querySelectorAll(
      "a[href], area[href], iframe[src], link[rel='stylesheet']");

  List<Destination> currentDestinations = <Destination>[];

  /// TODO: add destinations to queue, but NOT as a side effect inside extractLink
  List<Link> links = linkElements
      .map((element) => extractLink(current.finalUri, baseUri, element,
          const ["href", "src"], currentDestinations,
          parseable: true))
      .toList(growable: false);

  // Find resources
  var resourceElements =
      doc.querySelectorAll("link[href], [src], object[data]");
  Iterable<Link> currentResourceLinks = resourceElements.map((element) =>
      extractLink(current.finalUri, baseUri, element,
          const ["src", "href", "data"], currentDestinations));

  links.addAll(currentResourceLinks);

  // TODO: add srcset extractor (will create multiple links per element)

  checked.wasParsed = true;
  return FetchResults(checked, links);
}
