library linkcheck.worker;

import 'dart:async';
import 'dart:convert';
import 'dart:io' hide Link;
import 'dart:isolate';

import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:source_span/source_span.dart';
import 'package:stream_channel/stream_channel.dart';

import '../destination.dart';
import '../link.dart';
import '../origin.dart';
import '../parsers/css.dart';
import '../parsers/html.dart';
import '../uri_glob.dart';
import 'fetch_options.dart';
import 'fetch_results.dart';

const addHostGlobVerb = "ADD_HOST";
const checkDoneVerb = "CHECK_DONE";
const checkVerb = "CHECK";
const dataKey = "data";
const dieMessage = const {verbKey: dieVerb};
const dieVerb = "DIE";
const infoFromWorkerVerb = "INFO_FROM_WORKER";
const unrecognizedMessage = const {verbKey: unrecognizedVerb};
const unrecognizedVerb = "UNRECOGNIZED";
const verbKey = "message";


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

  // Process all destinations that cannot or shouldn't be HTML-parsed.
  if (current.statusCode != 200 ||
      !options.matchesAsInternal(current.finalUri) ||
      !current.isParseableMimeType /* TODO: add SVG/XML */) {
    return new FetchResults(checked, null);
  }

  String content;
  try {
    Converter<List<int>, String> decoder;
    if (current.contentType.charset == LATIN1.name) {
      // Some sites still use LATIN-1 for performance reasons.
      decoder = LATIN1.decoder;
    } else {
      decoder = UTF8.decoder;
    }
    content = await response.transform(decoder).join();
  } on FormatException {
    // TODO: make warning instead, record in current, continue
    throw new UnsupportedError("We don't support any encoding other than "
        "utf-8 and iso-8859-1 (latin-1). Crawled site has explicit charset "
        "'${current.contentType}' and couldn't be parsed by UTF8.");
  }

  if (current.statusCode == 200 && current.isCssMimeType) {
    return parseCss(content, current, checked);
  }

  // TODO: detect WEBrick/1.3.1 (Ruby/2.3.1/2016-04-26) (and potentially
  // other ugly index files).

  return parseHtml(content, uri, current, checked);
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

class Worker {
  StreamChannel<Map> _channel;
  StreamSink<Map> _sink;
  Stream<Map> _stream;

  String name;

  Destination destinationToCheck;
  bool get idle => destinationToCheck == null;

  bool _spawned = false;
  bool get spawned => _spawned;

  StreamSink<Map> get sink => _sink;

  Stream<Map> get stream => _stream;

  Future<Null> spawn() async {
    assert(_channel == null);
    _channel = await _spawnWorker();
    _sink = _channel.sink;
    _stream = _channel.stream;
    _spawned = true;
  }

  String toString() => "Worker<$name>";
}
