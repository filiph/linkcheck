library linkcheck.fetch_options;

import 'dart:async';

import '../uri_glob.dart';
import 'worker.dart';

/// The set of known facts and options for the Worker to use when fetching.
class FetchOptions {
  final _compiledHostGlobs = <UriGlob>[];
  final headIncompatible = <String>{}; // TODO: send to main
  // TODO: hashmap of known problematic servers etc. = List<String,ServerInfo>

  final StreamSink<Map<String, Object>> _sink;

  FetchOptions(this._sink);

  void addHostGlobs(List<String> values) {
    for (String value in values) {
      _compiledHostGlobs.add(UriGlob(value));
    }
  }

  void info(String message) {
    _sink.add(<String, Object>{verbKey: infoFromWorkerVerb, dataKey: message});
  }

  /// Returns true if the provided [uri] should be considered internal. This
  /// works through globbing the [_compiledHostGlobs] set.
  bool matchesAsInternal(Uri uri) {
    return _compiledHostGlobs.any((glob) => glob.matches(uri));
  }
}
