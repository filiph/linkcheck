import 'package:cli_pkg/cli_pkg.dart' as pkg;
import 'package:grinder/grinder.dart';

void main(List<String> args) {
  pkg.name.value = 'linkcheck';
  pkg.humanName.value = 'linkcheck';
  pkg.githubRepo.value = 'filiph/linkcheck';
  pkg.addAllTasks();
  grind(args);
}

@DefaultTask()
@Task()
Future<dynamic> test() => TestRunner().testAsync();

@Task()
void clean() => defaultClean();
