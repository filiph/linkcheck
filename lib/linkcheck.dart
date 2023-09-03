import 'dart:async';
import 'dart:io' hide Link;

import 'package:args/args.dart';
import 'package:console/console.dart';

import 'src/crawl.dart' show CrawlResult, crawl;
import 'src/parsers/url_skipper.dart';
import 'src/writer_report.dart' show reportForWriters;

export 'src/crawl.dart' show CrawlResult, crawl;
export 'src/destination.dart' show Destination;
export 'src/link.dart' show Link;
export 'src/origin.dart' show Origin;
export 'src/writer_report.dart' show reportForWriters;

const anchorFlag = 'check-anchors';
const ansiFlag = 'nice';
const connectionFailuresAsWarnings = 'connection-failures-as-warnings';
const debugFlag = 'debug';
const defaultUrl = 'http://localhost:8080/';
const externalFlag = 'external';
const helpFlag = 'help';
const hostsFlag = 'hosts';
const inputFlag = 'input-file';
const redirectFlag = 'show-redirects';
const skipFlag = 'skip-file';
const version = '3.1.0';
const versionFlag = 'version';
final _portOnlyRegExp = RegExp(r'^:\d+$');

void printStats(CrawlResult result, int broken, int withWarning, int withInfo,
    int withRedirect, bool showRedirects, bool ansiTerm, Stdout stdout) {
  // Redirect printing for better testing.
  void print(Object object) => stdout.writeln(object);

  final links = result.links;
  final count = result.destinations.length;
  final ignored = result.destinations
      .where((destination) =>
          destination.wasDeniedByRobotsTxt ||
          destination.isUnsupportedScheme ||
          (destination.isExternal && !destination.wasTried))
      .length;
  final leftUntried =
      result.destinations.where((destination) => !destination.wasTried).length;
  final checked = count - leftUntried;

  if (ansiTerm) {
    Console.write('\r');
    Console.eraseLine(3);
    final pen = TextPen();
    if (links.isEmpty) {
      var wasLocalhost = false;
      if (result.destinations.isNotEmpty &&
          !result.destinations.first.isInvalid &&
          result.destinations.first.uri.host == 'localhost') {
        wasLocalhost = true;
      }
      pen
          .red()
          .text('Error. ')
          .normal()
          .text("Couldn't connect or find any links.")
          .text(wasLocalhost ? ' Have you started the server?' : '')
          .print();
    } else if (broken == 0 && withWarning == 0 && withInfo == 0) {
      pen
          .green()
          .text('Perfect. ')
          .normal()
          .text('Checked ${links.length} links, $checked destination URLs')
          .lightGray()
          .text(ignored > 0 ? ' ($ignored ignored)' : '')
          .normal()
          .text(showRedirects && withRedirect > 0
              ? withRedirect == 1
                  ? ', 1 has redirect(s)'
                  : ', $withRedirect have redirect(s)'
              : '')
          .text('.')
          .print();
    } else if (broken == 0 && withWarning == 0) {
      pen
          .cyan()
          .text('Info. ')
          .normal()
          .text('Checked ${links.length} links, $checked destination URLs')
          .lightGray()
          .text(ignored > 0 ? ' ($ignored ignored)' : '')
          .normal()
          .text(', ')
          .text(showRedirects && withRedirect > 0
              ? withRedirect == 1
                  ? '1 has redirect(s), '
                  : '$withRedirect have redirect(s), '
              : '')
          .text('0 have warnings or errors')
          .text(withInfo > 0 ? ', $withInfo have info' : '')
          .text('.')
          .print();
    } else if (broken == 0) {
      pen
          .yellow()
          .text('Warnings. ')
          .normal()
          .text('Checked ${links.length} links, $checked destination URLs')
          .lightGray()
          .text(ignored > 0 ? ' ($ignored ignored)' : '')
          .normal()
          .text(', ')
          .text(showRedirects && withRedirect > 0
              ? withRedirect == 1
                  ? '1 has redirect(s), '
                  : '$withRedirect have redirect(s), '
              : '')
          .text(withWarning == 1
              ? '1 has a warning'
              : '$withWarning have warnings')
          .text(withInfo > 0 ? ', $withInfo have info' : '')
          .text('.')
          .print();
    } else {
      pen
          .red()
          .text('Errors. ')
          .normal()
          .text('Checked ${links.length} links, $checked destination URLs')
          .lightGray()
          .text(ignored > 0 ? ' ($ignored ignored)' : '')
          .normal()
          .text(', ')
          .text(showRedirects && withRedirect > 0
              ? withRedirect == 1
                  ? '1 has redirect(s), '
                  : '$withRedirect have redirect(s), '
              : '')
          .text(broken == 1 ? '1 has error(s), ' : '$broken have errors, ')
          .text(withWarning == 1
              ? '1 has warning(s)'
              : '$withWarning have warnings')
          .text(withInfo > 0 ? ', $withInfo have info' : '')
          .text('.')
          .print();
    }
  } else {
    print('\nStats:');
    print('${links.length.toString().padLeft(8)} links');
    if (showRedirects) {
      print('${withRedirect.toString().padLeft(8)} redirects');
    }
    print('${checked.toString().padLeft(8)} destination URLs');
    print('${ignored.toString().padLeft(8)} URLs ignored');
    print('${withWarning.toString().padLeft(8)} warnings');
    print('${broken.toString().padLeft(8)} errors');
  }
}

/// Parses command-line [arguments] and runs the crawl.
///
/// Provide `dart:io` [Stdout] as the second argument for normal operation,
/// or provide a mock for testing.
Future<int> run(List<String> arguments, Stdout stdout) async {
  // Redirect output to injected [stdout] for better testing.
  void print(Object message) => stdout.writeln(message);

  final parser = ArgParser(allowTrailingOptions: true)
    ..addFlag(helpFlag,
        abbr: 'h', negatable: false, help: 'Prints this usage help.')
    ..addFlag(versionFlag, abbr: 'v', negatable: false, help: 'Prints version.')
    ..addFlag(externalFlag,
        abbr: 'e',
        negatable: false,
        help: 'Check external (remote) links, too. By '
            'default, the tool only checks internal links.')
    ..addFlag(redirectFlag,
        help: 'Also report all links that point at a redirected URL.')
    ..addFlag(anchorFlag,
        help: 'Report links that point at a missing anchor.', defaultsTo: true)
    ..addSeparator('Advanced')
    ..addOption(inputFlag,
        abbr: 'i',
        help: 'Get list of URLs from the given text file (one URL per line).')
    ..addOption(skipFlag,
        help: 'Get list of URLs to skip from given text file (one RegExp '
            'pattern per line).')
    ..addMultiOption(hostsFlag,
        splitCommas: true,
        help: 'Paths to check. By default, the crawler '
            "doesn't parse HTML on sites with different path than the seed"
            'URIs. If your site spans multiple domains and you want to check '
            'HTML everywhere, use this. Provide as a glob, e.g. '
            'http://example.com/subdirectory/**.')
    ..addFlag(ansiFlag,
        help: 'Use ANSI terminal capabilities for nicer input. Turn this off '
            'if the output is broken.',
        defaultsTo: true)
    ..addFlag(connectionFailuresAsWarnings,
        help: 'Report connection failures as warnings rather than errors.')
    ..addFlag(debugFlag,
        abbr: 'd', negatable: false, help: 'Debug mode (very verbose).');

  final argResults = parser.parse(arguments);

  if (argResults[helpFlag] == true) {
    print('Linkcheck will crawl given site and check links.\n');
    print('usage: linkcheck [switches] [url]\n');
    print(parser.usage);
    return 0;
  }

  if (argResults[versionFlag] == true) {
    print('linkcheck version $version');
    return 0;
  }

  final ansiTerm = argResults[ansiFlag] == true && stdout.hasTerminal;
  final reportConnectionFailuresAsWarnings =
      argResults[connectionFailuresAsWarnings] == true;
  final verbose = argResults[debugFlag] == true;
  final shouldCheckExternal = argResults[externalFlag] == true;
  final showRedirects = argResults[redirectFlag] == true;
  final shouldCheckAnchors = argResults[anchorFlag] == true;
  final inputFile = argResults[inputFlag] as String?;
  final skipFile = argResults[skipFlag] as String?;

  var urls = argResults.rest.toList();
  var skipper = UrlSkipper.empty();

  if (inputFile != null) {
    final file = File(inputFile);
    try {
      urls.addAll(file.readAsLinesSync().where((url) => url.isNotEmpty));
    } on FileSystemException catch (e) {
      print("Can't read input file '$inputFile': $e");
      return 2;
    }
  }

  if (skipFile != null) {
    final file = File(skipFile);
    try {
      skipper = UrlSkipper(file.path, file.readAsLinesSync());
    } on FileSystemException catch (e) {
      print("Can't read skip file '$skipFile': $e");
      return 2;
    }
  }

  urls = urls.map(_sanitizeSeedUrl).toList();

  if (urls.isEmpty) {
    print('No URL given, checking $defaultUrl');
    urls.add(defaultUrl);
  } else if (verbose) {
    print('Reading URLs:');
    urls.forEach(print);
  }

  // TODO: exit gracefully if provided URL isn't a parseable URI
  final uris = urls.map((url) => Uri.parse(url)).toList(growable: false);
  Set<String> hosts;
  if ((argResults[hostsFlag] as Iterable<String>).isNotEmpty) {
    hosts = Set<String>.from(argResults[hostsFlag] as Iterable<String>);
  } else {
    // No host globs provided. Using the default (http://example.com/**).
    hosts = uris.map((uri) {
      var url = uri.toString();
      if (uri.path.isEmpty) return '$url/**';
      if (uri.path == '/') return '$url**';
      if (url.endsWith('/')) url = url.substring(0, url.length - 1);
      return '$url**';
    }).toSet();
  }

  // Start the actual crawl and await the result.
  final result = await crawl(uris, hosts, shouldCheckExternal, skipper, verbose,
      ansiTerm, ProcessSignal.sigint.watch(), stdout);

  final broken = result.destinations
      .where((destination) =>
          destination.wasTried &&
          destination.isBroken &&
          (!reportConnectionFailuresAsWarnings || !destination.didNotConnect))
      .length;

  final withWarning = result.links
      .where((link) =>
          link.hasWarning(shouldCheckAnchors) ||
          reportConnectionFailuresAsWarnings && link.destination.didNotConnect)
      .length;

  final withInfo = result.links.where((link) => link.hasInfo).length;

  final withRedirects =
      result.links.where((link) => link.destination.isRedirected).length;

  if (broken == 0 &&
      withWarning == 0 &&
      withInfo == 0 &&
      (!showRedirects || withRedirects == 0)) {
    printStats(result, broken, withWarning, withInfo, withRedirects,
        showRedirects, ansiTerm, stdout);
  } else {
    if (ansiTerm) {
      Console.write('\r');
      Console.eraseLine(3);
      print('Done crawling.                   ');
    }

    reportForWriters(
        result, ansiTerm, shouldCheckAnchors, showRedirects, stdout);

    printStats(result, broken, withWarning, withInfo, withRedirects,
        showRedirects, ansiTerm, stdout);
  }
  print('');

  if (broken > 0) return 2;
  if (withWarning > 0 || (showRedirects && withRedirects > 0)) return 1;
  return 0;
}

/// Takes input and makes it into a URL.
String _sanitizeSeedUrl(String url) {
  url = url.trim();
  if (_portOnlyRegExp.hasMatch(url)) {
    // From :4000 to http://localhost:4000/.
    url = 'http://localhost$url/';
  }

  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'http://$url';
  }

  return url;
}
