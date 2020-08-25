library linkcheck.executable;

import 'dart:async';
import 'dart:io';

import 'package:linkcheck/linkcheck.dart';

Future<int> main(List<String> arguments) async {
  await runZoned(() async {
    // Run the link checker. The returned value will be the program's exit code.
    exitCode = await run(arguments, stdout);
  }, onError: (Object e, StackTrace stackTrace) {
    stderr.writeln("INTERNAL ERROR: Sorry! Please open "
        "https://github.com/filiph/linkcheck/issues/new "
        "in your favorite browser and copy paste the following output there:"
        "\n");
    stderr.writeln(e.toString());
    stderr.writeln(stackTrace.toString());
    exitCode = 2;
  });
  return exitCode;
}
