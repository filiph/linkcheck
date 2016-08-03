library linkcheck.run;

import 'dart:async';
import 'dart:io' hide Link;

import 'package:args/args.dart';
import 'package:console/console.dart';

import 'src/crawl.dart' show crawl, CrawlResult;
import 'src/link.dart' show Link;
import 'src/writer_report.dart' show reportForWriters;

export 'src/crawl.dart' show crawl, CrawlResult;
export 'src/destination.dart' show Destination;
export 'src/link.dart' show Link;
export 'src/origin.dart' show Origin;
export 'src/writer_report.dart' show reportForWriters;

const ansiFlag = "nice";
const debugFlag = "debug";
const defaultUrl = "http://localhost:8080/";
const externalFlag = "external";
const helpFlag = "help";
const hostsFlag = "hosts";
const inputFlag = "input-file";
const version = "0.2.9";
const versionFlag = "version";
final _portOnlyRegExp = new RegExp(r"^:\d+$");

void printStats(CrawlResult result, int broken, int withWarning, int withInfo,
    bool ansiTerm, Stdout stdout) {
  // Redirect printing for better testing.
  void print(Object object) => stdout.writeln(object);

  Set<Link> links = result.links;
  int count = result.destinations.length;
  int externalIgnored = result.destinations
      .where((destination) =>
          destination.isExternal &&
          !destination.wasTried &&
          !destination.wasDeniedByRobotsTxt &&
          !destination.isUnsupportedScheme)
      .length;
  int checked = count - externalIgnored;

  if (ansiTerm) {
    Console.write("\r");
    Console.eraseLine(3);
    TextPen pen = new TextPen();
    if (links.isEmpty) {
      bool wasLocalhost = false;
      if (result.destinations.isNotEmpty &&
          !result.destinations.first.isInvalid &&
          result.destinations.first.uri.host == 'localhost') {
        wasLocalhost = true;
      }
      pen
          .red()
          .text("Error. ")
          .normal()
          .text("Couldn't connect or find any links.")
          .text(wasLocalhost ? " Have you started the server?" : "")
          .print();
    } else if (broken == 0 && withWarning == 0 && withInfo == 0) {
      pen
          .green()
          .text("Perfect. ")
          .normal()
          .text("Checked ${links.length} links, $checked destination URLs")
          .lightGray()
          .text(
              externalIgnored > 0 ? ' ($externalIgnored external ignored)' : '')
          .normal()
          .text(".")
          .print();
    } else if (broken == 0 && withWarning == 0) {
      pen
          .cyan()
          .text("Info. ")
          .normal()
          .text("Checked ${links.length} links, $checked destination URLs")
          .lightGray()
          .text(
              externalIgnored > 0 ? ' ($externalIgnored external ignored)' : '')
          .normal()
          .text(", ")
          .text("0 have warnings or errors")
          .text(withInfo > 0 ? ', $withInfo have info' : '')
          .text(".")
          .print();
    } else if (broken == 0) {
      pen
          .yellow()
          .text("Warnings. ")
          .normal()
          .text("Checked ${links.length} links, $checked destination URLs")
          .lightGray()
          .text(
              externalIgnored > 0 ? ' ($externalIgnored external ignored)' : '')
          .normal()
          .text(", ")
          .text(withWarning == 1
              ? "1 has a warning"
              : "$withWarning have warnings")
          .text(withInfo > 0 ? ', $withInfo have info' : '')
          .text(".")
          .print();
    } else {
      pen
          .red()
          .text("Errors. ")
          .normal()
          .text("Checked ${links.length} links, $checked destination URLs")
          .lightGray()
          .text(
              externalIgnored > 0 ? ' ($externalIgnored external ignored)' : '')
          .normal()
          .text(", ")
          .text(broken == 1 ? "1 has error(s), " : "$broken have errors, ")
          .text(withWarning == 1
              ? "1 has warning(s)"
              : "$withWarning have warnings")
          .text(withInfo > 0 ? ', $withInfo have info' : '')
          .text(".")
          .print();
    }
  } else {
    print("\nStats:");
    print("${links.length.toString().padLeft(8)} links");
    print("${checked.toString().padLeft(8)} destination URLs");
    print("${externalIgnored.toString().padLeft(8)} external URLs ignored");
    print("${withWarning.toString().padLeft(8)} warnings");
    print("${broken.toString().padLeft(8)} errors");
  }
}

/// Parses command-line [arguments] and runs the crawl.
///
/// Provide `dart:io` [Stdout] as the second argument for normal operation,
/// or provide a mock for testing.
Future<int> run(List<String> arguments, Stdout stdout) async {
  // TODO: capture all exceptions, use http://news.dartlang.org/2016/01/unboxing-packages-stacktrace.html, and present the error in a 'prod' way (showing: unrecoverable error, and only files in this library, and how to report it)

  // Redirect output to injected [stdout] for better testing.
  void print(Object message) => stdout.writeln(message);

  final parser = new ArgParser(allowTrailingOptions: true)
    ..addFlag(helpFlag,
        abbr: 'h', negatable: false, help: "Prints this usage help.")
    ..addFlag(versionFlag, abbr: 'v', negatable: false, help: "Prints version.")
    ..addFlag(externalFlag,
        abbr: 'e',
        negatable: false,
        help: "Check external (remote) links, too. By "
            "default, the tool only checks internal links.")
    ..addSeparator("Advanced")
    ..addOption(inputFlag,
        abbr: 'i',
        help: "Get list of URLs from the given "
            "text file (one URL per line).")
    ..addOption(hostsFlag,
        allowMultiple: true,
        splitCommas: true,
        help: "Paths to check. By default, the crawler "
            "doesn't parse HTML on sites with different path than the seed"
            "URIs. If your site spans multiple domains and you want to check "
            "HTML everywhere, use this. Provide as a glob, e.g. "
            "http://example.com/subdirectory/**.")
    ..addFlag(ansiFlag,
        help: "Use ANSI terminal capabilities for nicer input. Turn this off "
            "if the output is broken.",
        defaultsTo: true)
    ..addFlag(debugFlag,
        abbr: 'd', negatable: false, help: "Debug mode (very verbose).");

  final argResults = parser.parse(arguments);

  if (argResults[helpFlag]) {
    print("Linkcheck will crawl given site and check links.\n");
    print("usage: linkcheck [switches] [url]\n");
    print(parser.usage);
    return 0;
  }

  if (argResults[versionFlag]) {
    print("linkcheck version $version");
    return 0;
  }

  bool ansiTerm = argResults[ansiFlag] && stdout.hasTerminal;
  bool verbose = argResults[debugFlag];
  bool shouldCheckExternal = argResults[externalFlag];
  String inputFile = argResults[inputFlag];

  List<String> urls = argResults.rest.toList();

  if (inputFile != null) {
    var file = new File(inputFile);
    try {
      urls.addAll(file.readAsLinesSync().where((url) => url.isNotEmpty));
    } on FileSystemException {
      print("Can't read file '$inputFile'.");
      return 2;
    }
  }

  urls = urls.map(_sanitizeSeedUrl).toList();

  if (urls.isEmpty) {
    print("No URL given, checking $defaultUrl");
    urls.add(defaultUrl);
  } else if (verbose) {
    print("Reading URLs:");
    urls.forEach(print);
  }

  List<Uri> uris = urls.map((url) => Uri.parse(url)).toList();
  Set<String> hosts;
  if ((argResults[hostsFlag] as Iterable<String>).isNotEmpty) {
    hosts = new Set<String>.from(argResults[hostsFlag] as Iterable<String>);
  } else {
    // No host globs provided. Using the default (http://example.com/**).
    hosts = uris.map((uri) {
      var url = uri.toString();
      if (uri.path.isEmpty) return "$url/**";
      if (uri.path == '/') return "$url**";
      if (url.endsWith('/')) url = url.substring(0, url.length - 1);
      return "$url**";
    }).toSet();
  }

  // Start the actual crawl and await the result.
  CrawlResult result = await crawl(uris, hosts, shouldCheckExternal, verbose,
      ansiTerm, ProcessSignal.SIGINT.watch(), stdout);

  var broken = result.destinations
      .where((destination) => destination.wasTried && destination.isBroken)
      .length;

  var withWarning = result.links.where((link) => link.hasWarning).length;

  var withInfo = result.links.where((link) => link.hasInfo).length;

  if (broken == 0 && withWarning == 0 && withInfo == 0) {
    printStats(result, broken, withWarning, withInfo, ansiTerm, stdout);
  } else {
    if (ansiTerm) {
      Console.write("\r");
      Console.eraseLine(3);
      print("Done crawling.                   ");
    }

    reportForWriters(result, ansiTerm, stdout);

    printStats(result, broken, withWarning, withInfo, ansiTerm, stdout);
  }
  print("");

  if (broken > 0) return 2;
  if (withWarning > 0) return 1;
  return 0;
}

/// Takes input and makes it into a URL.
String _sanitizeSeedUrl(String url) {
  url = url.trim();
  if (_portOnlyRegExp.hasMatch(url)) {
    // From :4000 to http://localhost:4000/.
    url = "http://localhost$url/";
  }

  if (!url.startsWith("http://") && !url.startsWith("https://")) {
    url = "http://$url";
  }

  return url;
}
