import 'dart:io';

import 'package:linkcheck/linkcheck.dart';
import 'package:linkcheck/src/parsers/url_skipper.dart';

void main() async {
  // This package is mostly meant to be used as an executable. For that,
  // just follow installation instructions:
  // https://github.com/filiph/linkcheck#installation.
  //
  // But you can also use linkcheck in your own Dart projects.

  var results = await crawl(
    // A list of the seed URLs.
    [Uri.parse('http://localhost:8080')],
    // Glob of links to check. In this case, we want to crawl the whole site.
    {'http://localhost:8080/**'},
    // Whether or not to check outbound (external) links.
    false,
    // Which URLs to skip. In this case, we don't skip any files.
    UrlSkipper.empty(),
    // Verbose output?
    false,
    // Ansi terminal available?
    false,
    // A stream of Ctrl-C signals. Useful for quitting the crawl from outside.
    Stream<void>.empty(),
    // Standard output for linkcheck to use as progress indicator.
    stdout,
  );

  results.destinations
      // Take destinations that are broken (and not out of scope).
      .where((dest) => dest.isBroken && !dest.isExternal)
      // Simply print to console.
      .forEach(print);
}
