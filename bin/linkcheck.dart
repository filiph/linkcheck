library linkcheck.executable;

import 'dart:async';
import 'dart:io' hide Link;

import 'package:linkcheck/linkcheck.dart';

Future<int> main(List<String> arguments) async {
  exitCode = await run(arguments, stdout);
  return exitCode;
}