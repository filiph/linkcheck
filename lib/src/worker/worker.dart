library linkcheck.check.worker;

import 'dart:async';
import 'dart:convert';
import 'dart:io' hide Link;
import 'dart:isolate';

import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:stream_channel/stream_channel.dart';

import '../destination.dart';
import '../link.dart';
import '../origin.dart';
import '../uri_glob.dart';

const checkDoneVerb = "CHECK_DONE";
const checkVerb = "CHECK";
const dataKey = "data";
const dieMessage = const {verbKey: dieVerb};
const dieVerb = "DIE";
const addHostGlobVerb = "ADD_HOST";
const infoFromWorkerVerb = "INFO_FROM_WORKER";
const unrecognizedMessage = const {verbKey: unrecognizedVerb};
const unrecognizedVerb = "UNRECOGNIZED";
const verbKey = "message";

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

  var destinationUri = uri.resolve(reference);

  for (var existing in destinations) {
    if (destinationUri == existing.uri) {
      return new Link(origin, existing);
    }
  }

  Destination destination = new Destination(destinationUri);
  destination.isSource = parseable;
  destinations.add(destination);
  return new Link(origin, destination);
}

Future<FetchResults> fetch(
    Destination current, HttpClient client, FetchOptions options) async {
  DestinationResult checked = new DestinationResult.fromDestination(current);
  var uri = current.uri;

  options.info(uri.toString());

  // Fetch the HTTP response
  HttpClientResponse response;
  try {
    if (!current.isSource &&
        !options.headIncompatible.contains(current.uri.host)) {
      response = await _fetchHead(client, uri);
      if (response == null) {
        options.headIncompatible.add(current.uri.host);
        // TODO: let main isolate know (options.addHeadIncompatible)
      }
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
    checked.didNotConnect = true;
    return new FetchResults(checked, null);
  }

  checked.updateFromResponse(response);
  current.updateFromResult(checked);

  // Process all destinations that cannot or shouldn't be parsed.
  if (current.statusCode != 200 ||
      !options.matchesAsInternal(current.finalUri) ||
      !current.isHtmlMimeType /* TODO: add CSS, SVG/XML */) {
    return new FetchResults(checked, null);
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

  List<Destination> currentDestinations = <Destination>[];

  /// TODO: add destinations to queue, but NOT as a side effect inside extractLink
  List<Link> links = linkElements
      .map((element) => extractLink(
          uri, element, const ["href", "src"], currentDestinations, true))
      .toList();

  // Find resources
  var resourceElements =
      doc.querySelectorAll("link[href], [src], object[data]");
  Iterable<Link> currentResourceLinks = resourceElements.map((element) =>
      extractLink(uri, element, const ["src", "href", "data"],
          currentDestinations, false));

  links.addAll(currentResourceLinks);

  // TODO: add srcset extractor (will create multiple links per element)

  // TODO: take note of anchors on page, add it to current

  return new FetchResults(checked, links);
}

/// The entrypoint for the worker isolate.
void worker(SendPort port) {
  var channel = new IsolateChannel<Map>.connectSend(port);
  var sink = channel.sink;
  var stream = channel.stream;

  var client = new HttpClient();
  var options = new FetchOptions(sink);

  stream.listen((Map message) async {
    switch (message[verbKey]) {
      case dieVerb:
        client.close(force: true);
        sink.close();
        return null;
      case checkVerb:
        Destination destination =
            new Destination.fromMap(message[dataKey] as Map<String, Object>);
        var results = await fetch(destination, client, options);
        sink.add({verbKey: checkDoneVerb, dataKey: results.toMap()});
        return null;
      case addHostGlobVerb:
        options.addHostGlobs(message[dataKey] as List<String>);
        options.info("Globs received. Thanks!");
        return null;
      // TODO: add or update hosts map etc.
      default:
        sink.add(unrecognizedMessage);
    }
  });
}

/// Fetches the given [uri] by HTTP GET and returns a [HttpClientResponse].
Future<HttpClientResponse> _fetch(
    HttpClient client, Uri uri, Destination current) async {
  HttpClientRequest request = await client.getUrl(uri);
  var response = await request.close();
  return response;
}

/// Tries to fetch only by HTTP HEAD (instead of GET).
///
/// Some servers don't support this request, in which case they return HTTP
/// status code 405. If that's the case, this function returns `null`.
Future<HttpClientResponse> _fetchHead(HttpClient client, Uri uri) async {
  var request = await client.headUrl(uri);
  var response = await request.close();

  if (response.statusCode == 405) {
    return null;
  }
  return response;
}

/// Spawns a worker isolate and returns a [StreamChannel] for communicating with
/// it.
Future<StreamChannel<Map>> _spawnWorker() async {
  var port = new ReceivePort();
  await Isolate.spawn(worker, port.sendPort);
  return new IsolateChannel<Map>.connectReceive(port);
}

/// The set of known facts and options for the Worker to use when fetching.
class FetchOptions {
  final _compiledHostGlobs = new List<UriGlob>();
  final headIncompatible = new Set<String>(); // TODO: send to main
  // TODO: hashmap of known problematic servers etc.

  final StreamSink<Map> _sink;

  FetchOptions(this._sink);

  void addHostGlobs(List<String> values) {
    for (String value in values) {
      _compiledHostGlobs.add(new UriGlob(value));
    }
  }

  /// Returns true if the provided [uri] should be considered internal. This
  /// works through globbing the [_compiledHostGlobs] set.
  bool matchesAsInternal(Uri uri) {
    return _compiledHostGlobs.any((glob) => glob.matches(uri));
  }

  void info(String message) {
    _sink.add({verbKey: infoFromWorkerVerb, dataKey: message});
  }
}

class FetchResults {
  final DestinationResult checked;
  final List<Link> links;
  FetchResults(this.checked, this.links);

  FetchResults.fromMap(Map<String, Object> map)
      : this(
            new DestinationResult.fromMap(
                map["checked"] as Map<String, Object>),
            new List<Link>.from((map["links"] as List<Map>).map(
                (serialization) =>
                    new Link.fromMap(serialization as Map<String, Object>))));

  Map<String, Object> toMap() => {
        "checked": checked.toMap(),
        "links": links?.map((link) => link.toMap())?.toList() ?? []
      };
}

class Pool {
  /// The number of threads.
  final int count;

  List<Worker> _workers;

  final Set<String> _hostGlobs;

  StreamController<FetchResults> _fetchResultsSink =
      new StreamController<FetchResults>();
  Stream<FetchResults> fetchResults;

  StreamController<String> _messagesSink = new StreamController<String>();
  Stream<String> messages;

  Pool(this.count, this._hostGlobs) {
    fetchResults = _fetchResultsSink.stream;
    messages = _messagesSink.stream;
  }

  bool get allIdle => _workers.every((worker) => worker.idle);

  bool get allWorking => _workers.every((worker) => !worker.idle);

  void check(Destination destination) {
    var worker = pickWorker();
    worker.sink.add({verbKey: checkVerb, dataKey: destination.toMap()});
    worker.urlsToCheck.add(destination.url);
  }

  /// Sends host globs (e.g. http://example.com/**) to all the workers.
  void _addHostGlobs() {
    for (var worker in _workers) {
      worker.sink.add({verbKey: addHostGlobVerb, dataKey: _hostGlobs.toList()});
    }
  }

  Future<Null> close() async {
    await Future.wait(_workers.map((worker) async {
      worker.sink.add(dieMessage);
      await worker.sink.close();
    }));
  }

  Future<Null> spawn() async {
    _workers =
        new List<Worker>.generate(count, (i) => new Worker()..name = '$i');
    await Future.wait(_workers.map((worker) => worker.spawn()));
    _workers.forEach((worker) => worker.stream.listen((Map message) {
          switch (message[verbKey]) {
            case checkDoneVerb:
              var result = new FetchResults.fromMap(
                  message[dataKey] as Map<String, Object>);
              _fetchResultsSink.add(result);
              worker.urlsToCheck.remove(result.checked.url);
              return;
            case infoFromWorkerVerb:
              _messagesSink.add(message[dataKey]);
              return;
            default:
              throw new StateError("Unrecognized verb from Worker: "
                  "${message[verbKey]}");
          }
        }));
    _addHostGlobs();
  }

  /// Finds the worker with the least amount of jobs.
  Worker pickWorker() {
    for (var worker in _workers) {
      if (worker.idle) return worker;
    }
    throw new StateError("Attempt to use Pool when all workers are busy. "
        "Please make sure to wait until Pool.allWorking is false.");
  }
}

class Worker {
  StreamChannel<Map> _channel;
  StreamSink<Map> _sink;
  Stream<Map> _stream;

  String name;

  /// TODO: use to find out which destinations to re-check when a worker crashes
  final Set<String> urlsToCheck = new Set<String>();
  bool get idle => urlsToCheck.isEmpty;

  StreamSink<Map> get sink => _sink;

  Stream<Map> get stream => _stream;

  Future<Null> spawn() async {
    assert(_channel == null);
    _channel = await _spawnWorker();
    _sink = _channel.sink;
    _stream = _channel.stream;
  }

  String toString() => "Worker<$name>";
}
