library linkcheck.executable;

import 'dart:async';
import 'dart:io';

import 'package:linkcheck/linkcheck.dart';

Future<int> main(List<String> arguments) async {
  // Run the link checker. The returned value will be the program's exit code.
  exitCode = await run(arguments, stdout);
  return exitCode;
}