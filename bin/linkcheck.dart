import 'dart:async';
import 'dart:io' hide Link;

import 'package:args/args.dart';
import 'package:linkcheck/linkcheck.dart';
import 'package:console/console.dart';

Future<Null> main(List<String> arguments) async {
  // TODO: capture all exceptions, use http://news.dartlang.org/2016/01/unboxing-packages-stacktrace.html, and present the error in a 'prod' way (showing: unrecoverable error, and only files in this library, and how to report it)
  final parser = new ArgParser(allowTrailingOptions: true)
    ..addFlag(helpFlag, abbr: 'h', negatable: false, help: "Prints usage.")
    ..addFlag(ansiFlag,
        help: "Use ANSI terminal capabilities for nicer input.",
        defaultsTo: true)
    ..addFlag(verboseFlag, abbr: 'v', negatable: false, help: "Verbose mode.")
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
    ..addFlag(externalFlag,
        abbr: 'e',
        negatable: false,
        help: "Check external (remote) links, too. By "
            "default, the tool only checks internal links.");
  final argResults = parser.parse(arguments);

  if (argResults[helpFlag]) {
    print("Linkcheck will crawl given site and check links.\n");
    print("usage: linkcheck [switches] [url]");
    print(parser.usage);
    return;
  }

  bool ansiTerm = argResults[ansiFlag] && stdout.hasTerminal;
  bool verbose = argResults[verboseFlag];
  bool shouldCheckExternal = argResults[externalFlag];
  String inputFile = argResults[inputFlag];

  List<String> urls = argResults.rest.toList();

  if (inputFile != null) {
    var file = new File(inputFile);
    try {
      urls.addAll(file.readAsLinesSync().where((url) => url.isNotEmpty));
    } on FileSystemException {
      print("Can't read file '$inputFile'.");
      exitCode = 2;
      return;
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
      if (url.endsWith('/')) return "$url**";
      return "$url/**";
    }).toSet();
  }

  CrawlResult result = await crawl(uris, hosts, shouldCheckExternal, verbose,
      ansiTerm, ProcessSignal.SIGINT.watch());
  Set<Link> links = result.links;

  var broken = result.destinations
      .where((destination) => destination.wasTried && destination.isBroken)
      .length;

  var withWarning = links
      .where((link) => link.destination.wasTried && link.hasWarning)
      .length;

  if (broken == 0 && withWarning == 0) {
    printStats(result, broken, withWarning, ansiTerm);
  } else {
    if (ansiTerm) {
      Console.write("\r");
      Console.eraseLine(3);
      print("Done crawling.                   ");
    }

    reportForWriters(result, ansiTerm);

    printStats(result, broken, withWarning, ansiTerm);
  }
  print("");

  if (withWarning > 0) exitCode = 1;
  if (broken > 0) exitCode = 2;
}

void printStats(
    CrawlResult result, int broken, int withWarning, bool ansiTerm) {
  Set<Link> links = result.links;
  if (ansiTerm) {
    Console.write("\r");
    Console.eraseLine(3);
    TextPen pen = new TextPen();
    if (links.isEmpty) {
      pen
          .red()
          .text("Error. ")
          .normal()
          .text("Couldn't connect or find any links.")
          .print();
    } else if (broken == 0 && withWarning == 0) {
      pen
          .green()
          .text("Perfect. ")
          .normal()
          .text("${links.length} links checked.")
          .print();
    } else if (broken == 0) {
      pen
          .yellow()
          .text("Warnings. ")
          .normal()
          .text("${links.length} links checked, ")
          .text(withWarning == 1
              ? "1 has a warning"
              : "$withWarning have warnings.")
          .print();
    } else {
      pen
          .red()
          .text("Errors. ")
          .normal()
          .text("${links.length} links checked, "
              "$broken have errors, "
              "$withWarning have warnings.")
          .print();
    }
  } else {
    print("\n\nStats:");
    print("${links.length.toString().padLeft(8)} links checked");
    print("${withWarning.toString().padLeft(8)} have warnings");
    print("${broken.toString().padLeft(8)} are broken");
    print("");
  }
}

const defaultUrl = "http://localhost:4000/";

const ansiFlag = "nice";
const externalFlag = "external";
const helpFlag = "help";
const hostsFlag = "hosts";
const inputFlag = "input-file";
const verboseFlag = "verbose";

final _portOnlyRegExp = new RegExp(r"^:\d+$");

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
