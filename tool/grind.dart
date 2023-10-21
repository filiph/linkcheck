// ignore_for_file: unreachable_from_main

import 'package:cli_pkg/cli_pkg.dart' as pkg;
import 'package:grinder/grinder.dart';

void main(List<String> args) async {
  pkg.name.value = 'linkcheck';
  pkg.humanName.value = 'linkcheck';
  pkg.githubRepo.value = 'filiph/linkcheck';
  pkg.addAllTasks();
  await grind(args);
}

@DefaultTask()
@Task()
Future<dynamic> test() => TestRunner().testAsync();

@Task()
void clean() => defaultClean();
