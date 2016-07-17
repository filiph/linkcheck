library linkcheck.check;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' hide Link;

import 'package:console/console.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';

import 'destination.dart';
import 'link.dart';
import 'origin.dart';

Future<List<Link>> crawl(List<Uri> seeds, Set<String> hosts,
    bool shouldCheckExternal, bool verbose) async {
  bool isExternal(Uri uri) => !hosts.contains(uri.host);

  Console.init();
  var cursor = new Cursor();

  if (verbose) print("Crawl will start on the following URLs: $seeds");
  if (verbose) print("Crawl will check pages only on following hosts: $hosts");

  // The queue of destinations that haven't been tried yet. Destinations in
  // the front of the queue take precedence.
  Queue<Destination> open = new Queue<Destination>.from(
      seeds.map((uri) => new Destination(uri)..isSource = true));

  // The set of destinations that have been tried.
  Set<Destination> closed = new Set<Destination>();

  // List of hosts that do not support HTTP HEAD requests.
  Set<String> headIncompatible = new Set<String>();

  // TODO: add hashmap with robots. Special case for localhost

  Set<Link> links = new Set<Link>();

  var client = new HttpClient();

  int count = 0;
  if (!verbose) {
    cursor.write("Crawling sources: $count");
  }

  // TODO:
  // - a checkDestination takes destination and returns it updated with optional links on top
  // - paralellism: List<StreamChannel> isolates
  //   - listen to replies: either IDLE or results of a checkDestination
  //     - if IDLE and should quit => don't do anything
  //     - if IDLE and should quit and all others IDLE => all Done
  //     - if IDLE and open queue isNotEmpty => send new Destination to all IDLE isolates
  //     - if IDLE and all others IDLE and open queue empty => all done
  //     - results? add new links to open
  //   - send out first destinations
  //   - await allDone.future;

  // TODO: have openExternal and open - precedence to openExternal (take more time) but only if we also parse internal sources in parallel
  while (open.isNotEmpty) {
    // Get an unprocessed file.
    Destination current = open.removeFirst();
    current.isExternal = isExternal(current.uri);

    if (current.isExternal && !shouldCheckExternal) {
      _updateEquivalents(current, open, closed);
      continue;
    }

    if (verbose) {
      print(current.uriWithoutFragment);
      var sources = links.where((link) =>
          link.destination.uriWithoutFragment == current.uriWithoutFragment);
      print("- visiting because it was liked from $sources");
    } else {
      cursor.moveLeft(count.toString().length);
      count += 1;
      cursor.write(count.toString());
    }

    await _check(current, headIncompatible, client, closed, open, verbose, hosts, links);
  }

  // TODO: (optionally) check anchors

  client.close();

  assert(open.isEmpty);
  assert(closed.every((destination) =>
      destination.wasTried ||
      (destination.isExternal && !shouldCheckExternal)));

  return links.toList(growable: false);
}

Future<Null> _check(Destination current, Set<String> headIncompatible, HttpClient client, Set<Destination> closed, Queue<Destination> open, bool verbose, Set<String> hosts, Set<Link> links) async {
  var uri = current.uriWithoutFragment;

  // Fetch the HTTP response
  HttpClientResponse response;
  try {
    if (!current.isSource && !headIncompatible.contains(current.uri.host)) {
      response = await _fetchHead(client, uri);
      if (response == null) headIncompatible.add(current.uri.host);
    }

    if (response == null) {
      response = await _fetch(client, uri, current);
    }
  } on HttpException {
    // Leave response == null.
  } on SocketException {
    // Leave response == null.
  } on HandshakeException {
    // Leave response == null.
  }

  if (response == null) {
    // Request failed completely.
    // TODO: abort when we encounter X of these in a row
    //      print("\n\nERROR: Couldn't connect to $uri. Are you sure you've "
    //          "started the localhost server?");
    exitCode = 2;
    current.didNotConnect = true;
    assert(!closed.contains(current));
    _updateEquivalents(current, open, closed);
    closed.add(current);
    return;
  }

  current.updateFromResponse(response);
  if (verbose) {
    print("- HTTP ${current.statusCode}, ${current.contentType}");
  }

  // Process all destinations that cannot or shouldn't be parsed.
  if (current.statusCode != 200 ||
      !hosts.contains(current.finalUri.host) ||
      !current.isHtmlMimeType /* TODO: add CSS, SVG/XML */) {
    // Does not await for performance reasons.
    response.drain();

    assert(!closed.contains(current));
    _updateEquivalents(current, open, closed);
    closed.add(current);
    return;
  }

  String html;
  try {
    Converter<List<int>, String> decoder;
    if (current.contentType.charset == LATIN1.name) {
      // Some sites still use LATIN-1 for performance reasons.
      decoder = LATIN1.decoder;
    } else {
      decoder = UTF8.decoder;
    }
    html = await response.transform(decoder).join();
  } on FormatException {
    // TODO: make warning instead, record in current, continue
    throw new UnsupportedError("We don't support any encoding other than "
        "utf-8 and iso-8859-1 (latin-1). Crawled site has explicit charset "
        "'${current.contentType}' and couldn't be parsed by UTF8.");
  }

  // TODO: detect WEBrick/1.3.1 (Ruby/2.3.1/2016-04-26) (and potentially
  // other ugly index files).

  // Parse it
  var doc = parse(html, generateSpans: true, sourceUrl: uri.toString());

  // Find parseable destinations
  // TODO: add the following: media, meta refreshes, forms, metadata
  //   `<meta http-equiv="refresh" content="5; url=redirect.html">`
  // TODO: work with http://www.w3schools.com/tags/tag_base.asp (can be anywhere)
  // TODO: get <meta> robot directives - https://github.com/stevenvachon/broken-link-checker/blob/master/lib/internal/scrapeHtml.js#L164

  var linkElements = doc.querySelectorAll("a[href], area[href], iframe[src]");

  /// TODO: add destinations to queue, but NOT as a side effect inside extractLink
  List<Link> sourceLinks = linkElements
      .map((element) => extractLink(
          uri, element, const ["href", "src"], open, closed, true))
      .toList(growable: false);

  if (verbose)
    print("- found ${sourceLinks.length} links leading to "
        "${sourceLinks.map((link) => link.destination.uriWithoutFragment)
        .toSet().length} "
        "different URLs: "
        "${sourceLinks.map((link) => link.destination.uriWithoutFragment)
        .toSet()}");

  // TODO: Remove URIs that are not http/https

  links.addAll(sourceLinks);

  // Find resources
  var resourceElements =
      doc.querySelectorAll("link[href], [src], object[data]");
  List<Link> currentResourceLinks = resourceElements
      .map((element) => extractLink(
          uri, element, const ["src", "href", "data"], open, closed, false))
      .toList(growable: false);

  // TODO: add srcset extractor (will create multiple links per element)

  if (verbose) print("- found ${currentResourceLinks.length} resources");

  links.addAll(currentResourceLinks);

  // TODO: take note of anchors on page, add it to current

  assert(!closed.contains(current));
  _updateEquivalents(current, open, closed);
  closed.add(current);
}

void _updateEquivalents(
    Destination current, Queue<Destination> open, Set<Destination> closed) {
  List<Destination> equivalents = _getEquivalents(current, open).toList();
  for (var other in equivalents) {
    other.updateFrom(current);
    open.remove(other);
    assert(!closed.contains(other));
    closed.add(other);
  }
}

/// Tries to fetch only by HTTP HEAD (instead of GET).
///
/// Some servers don't support this request, in which case they return HTTP
/// status code 405. If that's the case, this function returns `null`.
Future<HttpClientResponse> _fetchHead(HttpClient client, Uri uri) async {
  var request = await client.headUrl(uri);
  var response = await request.close();

  if (response.statusCode == 405) {
    // Does not await for performance reasons.
    response.drain();
    return null;
  }
  return response;
}

/// Returns all destinations that share the same
/// [Destination.uriWithoutFragment] with [current].
Iterable<Destination> _getEquivalents(
        Destination current, Iterable<Destination> destinations) =>
    destinations.where((destination) =>
        destination.uriWithoutFragment == current.uriWithoutFragment);

/// Takes a DOM element and extracts a link from it.
///
/// The provided [attributes] will be checked in sequence.
///
/// Setting [parseable] to true will create a link to a destination with
/// [Destination.isSource] set to `true`. For example, links in <a href> are
/// often parseable, links in <img src> often aren't.
///
/// Re-uses Destination from [open] and [closed] if it already exists.
///
/// Also adds new destination to [open] if it doesn't already exist.
/// TODO: ^^^ fix this unexpected side effect
Link extractLink(
    Uri uri,
    Element element,
    final List<String> attributes,
    final Queue<Destination> open,
    final Iterable<Destination> closed,
    bool parseable) {
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

  var destinationUri = uri.resolve(reference);

  for (var existing in open) {
    if (destinationUri == existing.uri) {
      return new Link(origin, existing);
    }
  }

  for (var existing in closed) {
    if (destinationUri == existing.uri) {
      return new Link(origin, existing);
    }
  }

  Destination destination = new Destination(destinationUri);
  if (parseable) {
    destination.isSource = true;
    open.addFirst(destination);
  } else {
    open.addLast(destination);
  }
  return new Link(origin, destination);
}

/// Fetches the given [uri] by HTTP GET and returns a [HttpClientResponse].
Future<HttpClientResponse> _fetch(
    HttpClient client, Uri uri, Destination current) async {
  HttpClientRequest request = await client.getUrl(uri);
  var response = await request.close();
  return response;
}
