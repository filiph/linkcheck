import 'dart:async';
import 'dart:convert';
import 'dart:io' hide Link;
import 'dart:isolate';

import 'package:meta/meta.dart';
import 'package:stream_channel/isolate_channel.dart';
import 'package:stream_channel/stream_channel.dart';

import '../destination.dart';
import '../parsers/css.dart';
import '../parsers/html.dart';
import '../server_info.dart';
import 'fetch_options.dart';
import 'fetch_results.dart';

const dieMessage = WorkerTask(verb: WorkerVerb.die);
const unrecognizedMessage = WorkerTask(verb: WorkerVerb.unrecognized);
const userAgent = 'linkcheck tool (https://github.com/filiph/linkcheck)';

Future<ServerInfoUpdate> checkServer(
    String host, HttpClient client, FetchOptions options) async {
  final originalHost = host;

  int? port;
  if (host.contains(':')) {
    final parts = host.split(':');
    assert(parts.length == 2);
    host = parts.first;
    port = int.parse(parts.last);
  }

  final uri = Uri(scheme: 'http', host: host, port: port, path: '/robots.txt');

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
    content = '';
  }

  return ServerInfoUpdate(originalHost, robotsTxtContents: content);
}

Future<FetchResults> checkPage(
    Destination current, HttpClient client, FetchOptions options) async {
  final uri = current.uri;

  // Fetch the HTTP response
  HttpClientResponse? response;
  try {
    if (!current.isSource && !options.headIncompatible.contains(uri.host)) {
      response = await _fetchHead(client, uri);
      if (response == null) {
        options.headIncompatible.add(uri.host);
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
    final checked =
        DestinationResult.fromDestination(current, didNotConnect: true);
    return FetchResults(checked);
  }

  final checked = DestinationResult.fromResponse(current, response);

  current.updateFromResult(checked);

  if (current.statusCode != 200) {
    return FetchResults(checked);
  }

  if (!current.isParseableMimeType /* TODO: add SVG/XML */) {
    return FetchResults(checked);
  }

  final isExternal = !options.matchesAsInternal(current.finalUri);

  if (isExternal && !current.isHtmlMimeType) {
    // We only parse external HTML (to get anchors), not other mime types.
    return FetchResults(checked);
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
    return FetchResults(checked);
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
  final channel = IsolateChannel<WorkerTask>.connectSend(port);
  final sink = channel.sink;
  final stream = channel.stream;

  final client = HttpClient()..userAgent = userAgent;
  final options = FetchOptions(sink);

  var alive = true;

  stream.listen((WorkerTask message) async {
    switch (message.verb) {
      case WorkerVerb.die:
        client.close(force: true);
        alive = false;
        await sink.close();
        return;
      case WorkerVerb.checkPage:
        final destination = message.data as Destination;
        final fetchResults = await checkPage(destination, client, options);
        if (alive) {
          sink.add(
              WorkerTask(verb: WorkerVerb.checkPageDone, data: fetchResults));
        }
        return;
      case WorkerVerb.checkServer:
        final host = message.data as String;
        final serverUpdateResults = await checkServer(host, client, options);
        if (alive) {
          sink.add(WorkerTask(
              verb: WorkerVerb.checkServerDone, data: serverUpdateResults));
        }
        return;
      case WorkerVerb.addHostGlob:
        options.addHostGlobs(message.data as List<String>);
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
  final request = await client.getUrl(uri).timeout(connectionTimeout);
  final response = await request.close().timeout(responseTimeout);
  return response;
}

/// Tries to fetch only by HTTP HEAD (instead of GET).
///
/// Some servers don't support this request, in which case they return HTTP
/// status code 405. If that's the case, this function returns `null`.
Future<HttpClientResponse?> _fetchHead(HttpClient client, Uri uri) async {
  final request = await client.headUrl(uri).timeout(connectionTimeout);
  final response = await request.close().timeout(responseTimeout);

  if (response.statusCode == 405) {
    return null;
  }
  return response;
}

/// Spawns a worker isolate and returns a [StreamChannel] for communicating with
/// it.
Future<StreamChannel<WorkerTask>> _spawnWorker() async {
  final port = ReceivePort();
  await Isolate.spawn(worker, port.sendPort);
  return IsolateChannel<WorkerTask>.connectReceive(port);
}

class Worker {
  StreamChannel<WorkerTask>? _channel;

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

  StreamSink<WorkerTask> get sink => _channel!.sink;
  bool get spawned => _spawned;

  Stream<WorkerTask> get stream => _channel!.stream;

  Future<void> kill() async {
    if (!_spawned) return;
    _isKilled = true;
    final sinkToClose = sink;
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

@immutable
class WorkerTask {
  final WorkerVerb verb;
  final Object? data;

  const WorkerTask({required this.verb, this.data});
}

/// Different types of tasks which can be communicated to and from workers
enum WorkerVerb {
  addHostGlob,
  checkPage,
  checkPageDone,
  checkServer,
  checkServerDone,
  die,
  infoFromWorker,
  unrecognized
}
