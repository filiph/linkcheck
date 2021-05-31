import 'package:cli_pkg/cli_pkg.dart' as pkg;
import 'package:grinder/grinder.dart';

void main(List<String> args) {
  pkg.name.value = "linkcheck";
  pkg.humanName.value = "linkcheck";
  // FIXME: for testing purposes, should be "filiph/linkcheck"
  pkg.githubRepo.value = "mogztter/linkcheck";
  pkg.addAllTasks();
  grind(args);
}

@DefaultTask()
@Task()
Future test() => TestRunner().testAsync();

@Task()
void clean() => defaultClean();
