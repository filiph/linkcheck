import 'package:test/test.dart';

import 'package:linkcheck/src/worker/worker.dart';
import 'dart:async';

void main() {
  group("Glob", () {
    test("parses simple example", () {
      var sink = new StreamController<Map>();
      var options = new FetchOptions(sink);
      Uri uri = Uri.parse("http://localhost:4000/");
      options.addHostGlobs([uri.toString() + "**"]);
      expect(options.matchesAsInternal(uri), isTrue);
      sink.close();
    });
  });
}
