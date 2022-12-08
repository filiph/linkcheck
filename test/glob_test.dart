import 'package:test/test.dart';

import 'dart:async';
import 'package:linkcheck/src/worker/fetch_options.dart';

void main() {
  test("parses simple example", () {
    var sink = StreamController<Map<String, Object>>();
    var options = FetchOptions(sink);
    Uri uri = Uri.parse("http://localhost:4000/");
    options.addHostGlobs(["$uri**"]);
    expect(options.matchesAsInternal(uri), isTrue);
    sink.close();
  });

  test("parses localhost:4000/guides", () {
    var sink = StreamController<Map<String, Object>>();
    var options = FetchOptions(sink);
    Uri uri = Uri.parse("http://localhost:4000/guides");
    options.addHostGlobs(["$uri**"]);
    expect(options.matchesAsInternal(uri), isTrue);
    sink.close();
  });

  test("parses localhost:4000/guides/", () {
    var sink = StreamController<Map<String, Object>>();
    var options = FetchOptions(sink);
    Uri uri = Uri.parse("http://localhost:4000/guides/");
    options.addHostGlobs(["http://localhost:4000/guides**"]);
    expect(options.matchesAsInternal(uri), isTrue);
    sink.close();
  });
}
