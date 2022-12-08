import 'dart:async';
import 'dart:convert';
import 'dart:io' hide Link;
import 'dart:isolate';

import 'package:stream_channel/isolate_channel.dart';
import 'package:stream_channel/stream_channel.dart';

import '../destination.dart';
import '../parsers/css.dart';
import '../parsers/html.dart';
import '../server_info.dart';
import 'fetch_options.dart';
import 'fetch_results.dart';

const addHostGlobVerb = "ADD_HOST";
const checkPageDoneVerb = "CHECK_DONE";
const checkPageVerb = "CHECK";
const checkServerDoneVerb = "SERVER_CHECK_DONE";
const checkServerVerb = "CHECK_SERVER";
const dataKey = "data";
final dieMessage = {verbKey: dieVerb};
const dieVerb = "DIE";
const infoFromWorkerVerb = "INFO_FROM_WORKER";
final unrecognizedMessage = {verbKey: unrecognizedVerb};
const unrecognizedVerb = "UNRECOGNIZED";
const userAgent = "linkcheck tool (https://github.com/filiph/linkcheck)";

const verbKey = "message";

Future<ServerInfoUpdate> checkServer(
    String host, HttpClient client, FetchOptions options) async {
  var originalHost = host;

  int? port;
  if (host.contains(':')) {
    var parts = host.split(':');
    assert(parts.length == 2);
    host = parts.first;
    port = int.parse(parts.last);
  }

  Uri uri = Uri(scheme: "http", host: host, port: port, path: "/robots.txt");

  // Fetch the HTTP response
  HttpClientResponse? response;
  try {
    response = await _fetch(client, uri);
  } on TimeoutException {
    // Leave response == null.
  } on HttpException {
    // Leave response == null.
  } on SocketException {
    // Leave response == null.
  } on HandshakeException {
    // Leave response == null.
  }

  // Request failed completely.
  if (response == null) {
    return ServerInfoUpdate.didNotConnect(originalHost);
  }

  // No robots.txt.
  if (response.statusCode != 200) {
    return ServerInfoUpdate(originalHost);
  }

  String content;
  try {
    Converter<List<int>, String> decoder;
    if (response.headers.contentType?.charset == latin1.name) {
      // Some sites still use LATIN-1 for performance reasons.
      decoder = latin1.decoder;
    } else {
      // But if content type is not set or is not LATIN-1, we assume UTF-8.
      decoder = utf8.decoder;
    }
    content = await response.cast<List<int>>().transform(decoder).join();
  } on FormatException {
    // TODO: report as a warning
    content = "";
  }

  return ServerInfoUpdate(originalHost, robotsTxtContents: content);
}

Future<FetchResults> checkPage(
    Destination current, HttpClient client, FetchOptions options) async {
  DestinationResult checked = DestinationResult.fromDestination(current);
  var uri = current.uri;

  // Fetch the HTTP response
  HttpClientResponse? response;
  try {
    if (!current.isSource &&
        !options.headIncompatible.contains(current.uri.host)) {
      response = await _fetchHead(client, uri);
      if (response == null) {
        options.headIncompatible.add(current.uri.host);
        // TODO: let main isolate know (options.addHeadIncompatible)
      }
    }

    response ??= await _fetch(client, uri);
  } on TimeoutException {
    // Leave response == null.
  } on HttpException {
    // Leave response == null.
  } on SocketException {
    // Leave response == null.
  } on HandshakeException {
    // Leave response == null.
  }

  if (response == null) {
    // Request failed completely.
    checked.didNotConnect = true;
    return FetchResults(checked, const []);
  }

  checked.updateFromResponse(response);
  current.updateFromResult(checked);

  if (current.statusCode != 200) {
    return FetchResults(checked, const []);
  }

  if (!current.isParseableMimeType /* TODO: add SVG/XML */) {
    return FetchResults(checked, const []);
  }

  bool isExternal = !options.matchesAsInternal(current.finalUri);

  if (isExternal && !current.isHtmlMimeType) {
    // We only parse external HTML (to get anchors), not other mime types.
    return FetchResults(checked, const []);
  }

  String content;
  try {
    Converter<List<int>, String> decoder;
    if (current.contentType?.charset == latin1.name) {
      // Some sites still use LATIN-1 for performance reasons.
      decoder = latin1.decoder;
    } else {
      decoder = utf8.decoder;
    }
    content = await response.cast<List<int>>().transform(decoder).join();
  } on FormatException {
    // TODO: report as a warning
    checked.hasUnsupportedEncoding = true;
    return FetchResults(checked, const []);
  }

  if (current.isCssMimeType) {
    return parseCss(content, current, checked);
  }

  // TODO: detect WEBrick/1.3.1 (Ruby/2.3.1/2016-04-26) (and potentially
  // other ugly index files).

  return parseHtml(content, uri, current, checked, isExternal);
}

/// The entrypoint for the worker isolate.
void worker(SendPort port) {
  var channel = IsolateChannel<Map<String, Object>>.connectSend(port);
  var sink = channel.sink;
  var stream = channel.stream;

  var client = HttpClient()..userAgent = userAgent;
  var options = FetchOptions(sink);

  bool alive = true;

  stream.listen((Map<String, Object> message) async {
    switch (message[verbKey] as String) {
      case dieVerb:
        client.close(force: true);
        alive = false;
        await sink.close();
        return;
      case checkPageVerb:
        Destination destination =
            Destination.fromMap(message[dataKey] as Map<String, Object>);
        var results = await checkPage(destination, client, options);
        if (alive) {
          sink.add({verbKey: checkPageDoneVerb, dataKey: results.toMap()});
        }
        return;
      case checkServerVerb:
        String host = message[dataKey] as String;
        ServerInfoUpdate results = await checkServer(host, client, options);
        if (alive) {
          sink.add({verbKey: checkServerDoneVerb, dataKey: results.toMap()});
        }
        return;
      case addHostGlobVerb:
        options.addHostGlobs(message[dataKey] as List<String>);
        return;
      // TODO: add to server info from main isolate
      default:
        sink.add(unrecognizedMessage);
    }
  });
}

const connectionTimeout = Duration(seconds: 5);
const responseTimeout = Duration(seconds: 5);
final fetchTimeout = connectionTimeout + responseTimeout;

/// Fetches the given [uri] by HTTP GET and returns a [HttpClientResponse].
Future<HttpClientResponse> _fetch(HttpClient client, Uri uri) async {
  HttpClientRequest request =
      await client.getUrl(uri).timeout(connectionTimeout);
  var response = await request.close().timeout(responseTimeout);
  return response;
}

/// Tries to fetch only by HTTP HEAD (instead of GET).
///
/// Some servers don't support this request, in which case they return HTTP
/// status code 405. If that's the case, this function returns `null`.
Future<HttpClientResponse?> _fetchHead(HttpClient client, Uri uri) async {
  var request = await client.headUrl(uri).timeout(connectionTimeout);
  var response = await request.close().timeout(responseTimeout);

  if (response.statusCode == 405) {
    return null;
  }
  return response;
}

/// Spawns a worker isolate and returns a [StreamChannel] for communicating with
/// it.
Future<StreamChannel<Map<String, Object>>> _spawnWorker() async {
  var port = ReceivePort();
  await Isolate.spawn(worker, port.sendPort);
  return IsolateChannel<Map<String, Object>>.connectReceive(port);
}

class Worker {
  StreamChannel<Map<String, Object>>? _channel;

  final String name;

  Destination? destinationToCheck;

  String? serverToCheck;

  bool _spawned = false;

  bool _isKilled = false;

  Worker(this.name);

  bool get idle =>
      destinationToCheck == null &&
      serverToCheck == null &&
      _spawned &&
      !_isKilled;

  bool get isKilled => _isKilled;

  StreamSink<Map<String, Object>> get sink => _channel!.sink;
  bool get spawned => _spawned;

  Stream<Map<String, Object>> get stream => _channel!.stream;

  Future<void> kill() async {
    if (!_spawned) return;
    _isKilled = true;
    var sinkToClose = sink;
    sinkToClose.add(dieMessage);
    await sinkToClose.close();
  }

  Future<void> spawn() async {
    assert(_channel == null);
    _channel = await _spawnWorker();
    _spawned = true;
  }

  @override
  String toString() => 'Worker<$name>';
}

class SpawnedWorker {}
