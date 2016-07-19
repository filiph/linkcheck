import 'dart:async';
import 'dart:io' hide Link;

import 'package:args/args.dart';
import 'package:linkcheck/linkcheck.dart';

Future<Null> main(List<String> arguments) async {
  final parser = new ArgParser(allowTrailingOptions: true)
    ..addFlag(helpFlag, abbr: 'h', negatable: false, help: "Prints usage.")
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

  bool verbose = argResults[verboseFlag];
  bool shouldCheckExternal = argResults[externalFlag];
  String inputFile = argResults[inputFlag];

  final List<String> urls = argResults.rest.toList();

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

  // TODO: sanitize and canonicalize URLs (localhost add http, :4000 add localhost)

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

  List<Link> links = await crawl(uris, hosts, shouldCheckExternal, verbose);

  var broken = links
      .where((link) => link.destination.wasTried && link.destination.isBroken)
      .toList(growable: false);

  print("\n\nStats:");
  print("${links.length.toString().padLeft(8)} links checked");
  print("${broken.length.toString().padLeft(8)} possibly broken links found");
  print("");

  reportForWriters(broken);

  if (broken.isNotEmpty) exitCode = 2;
}

const defaultUrl = "http://localhost:4000/";

const externalFlag = "external";
const helpFlag = "help";
const hostsFlag = "hosts";
const inputFlag = "input-file";
const verboseFlag = "verbose";
