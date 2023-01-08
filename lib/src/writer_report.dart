import 'dart:io' show Stdout;
import 'dart:math' show min;

import 'package:console/console.dart';

import 'crawl.dart' show CrawlResult;
import 'link.dart';

/// Writes the reports from the perspective of a website writer - which pages
/// reference broken links.
void reportForWriters(CrawlResult result, bool ansiTerm,
    bool shouldCheckAnchors, bool showRedirects, Stdout stdout) {
  void print(Object message) => stdout.writeln(message);

  print('');

  final links = result.links;

  /// Links that were found broken or had a warning or were redirected.
  final problematicLinks = links
      .where((link) =>
          !link.destination.isUnsupportedScheme &&
          !link.wasSkipped &&
          (link.destination.isInvalid ||
              link.destination.wasTried &&
                  (link.destination.isBroken ||
                      link.hasWarning(shouldCheckAnchors) ||
                      (showRedirects && link.destination.isRedirected))))
      .toList(growable: false);

  final deniedByRobots = result.destinations
      .where((destination) => destination.wasDeniedByRobotsTxt)
      .toList(growable: false);
  deniedByRobots.sort((a, b) => a.url.compareTo(b.url));

  final sourceUris = problematicLinks
      .map((link) => link.origin.uri)
      .toSet()
      .toList(growable: false);
  sourceUris.sort((a, b) => a.toString().compareTo(b.toString()));

  TextPen? ansiPen;
  if (ansiTerm) {
    ansiPen = TextPen();
  }

  final brokenSeeds = result.destinations
      .where((destination) => destination.isSeed && destination.isBroken)
      .toList(growable: false);
  brokenSeeds.sort((a, b) => a.toString().compareTo(b.toString()));

  if (brokenSeeds.isNotEmpty) {
    print('Provided URLs failing:');
    for (final destination in brokenSeeds) {
      if (ansiPen != null) {
        ansiPen
            .reset()
            .yellow()
            .text(destination.url)
            .lightGray()
            .text(' (')
            .red()
            .text(destination.statusDescription)
            .lightGray()
            .text(')')
            .normal()
            .print();
      } else {
        print('${destination.url} (${destination.statusDescription})');
      }
    }

    print('');
  }

  if (deniedByRobots.isNotEmpty) {
    print('Access to these URLs denied by robots.txt, '
        "so we couldn't check them:");
    for (final destination in deniedByRobots) {
      if (ansiPen != null) {
        ansiPen
            .reset()
            .normal()
            .text('- ')
            .yellow()
            .text(destination.url)
            .normal()
            .print();
      } else {
        print('- ${destination.url}');
      }
    }

    print('');
  }

  // TODO: summarize when there are huge amounts of sourceURIs for a broken link
  // TODO: report invalid links

  for (final uri in sourceUris) {
    if (ansiPen != null) {
      printWithAnsi(uri, problematicLinks, ansiPen);
    } else {
      printWithoutAnsi(uri, problematicLinks, stdout);
    }
  }

  final brokenLinks =
      problematicLinks.where((link) => link.hasError).toList(growable: false);
  if (brokenLinks.isNotEmpty &&
      brokenLinks.length < problematicLinks.length / 2) {
    // Reiterate really broken links if the listing above is mostly warnings
    // with only a minority of errors. The user cares about errors first.
    print('');
    print('Summary of most serious issues:');
    print('');

    final brokenUris = brokenLinks
        .map((link) => link.origin.uri)
        .toSet()
        .toList(growable: false);
    brokenUris.sort((a, b) => a.toString().compareTo(b.toString()));

    for (final uri in brokenUris) {
      if (ansiPen != null) {
        printWithAnsi(uri, brokenLinks, ansiPen);
      } else {
        printWithoutAnsi(uri, brokenLinks, stdout);
      }
    }
  }
}

void printWithAnsi(Uri uri, List<Link> broken, TextPen pen) {
  pen.reset();
  pen.setColor(Color.YELLOW).text(uri.toString()).normal().print();

  final links = broken.where((link) => link.origin.uri == uri);
  for (final link in links) {
    final tag = _buildTagSummary(link);
    pen.reset();
    pen
        .normal()
        .text('- ')
        .lightGray()
        .text('(')
        .normal()
        .text('${link.origin.span.start.line + 1}')
        .lightGray()
        .text(':')
        .normal()
        .text('${link.origin.span.start.column}')
        .lightGray()
        .text(') ')
        .magenta()
        .text(tag)
        .lightGray()
        .text('=> ')
        .normal()
        .text(link.destination.url)
        .lightGray()
        .text(link.fragment == null ? '' : '#${link.fragment}')
        .text(' (')
        .setColor(link.hasError ? Color.RED : Color.YELLOW)
        .text(link.destination.statusDescription)
        .yellow()
        .text(!link.hasError && link.breaksAnchor ? ' but missing anchor' : '')
        .lightGray()
        .text(')')
        .normal()
        .print();

    if (link.destination.isRedirected) {
      print('  - redirect path:');
      var currentUrl = link.destination.url;
      for (final redirect in link.destination.redirects) {
        print('    - $currentUrl (${redirect.statusCode})');
        currentUrl = redirect.url;
      }
      print('    - $currentUrl (${link.destination.statusCode})');
    }
  }
  print('');
}

void printWithoutAnsi(Uri uri, List<Link> broken, Stdout stdout) {
  // Redirect output to injected [stdout] for better testing.
  void print(Object message) => stdout.writeln(message);

  print(uri);

  final links = broken.where((link) => link.origin.uri == uri);
  for (final link in links) {
    final tag = _buildTagSummary(link);
    final linkFragment = link.fragment;
    print('- (${link.origin.span.start.line + 1}'
        ':${link.origin.span.start.column}) '
        '$tag'
        '=> ${link.destination.url}'
        "${linkFragment == null ? '' : '#$linkFragment'} "
        '(${link.destination.statusDescription}'
        "${!link.destination.isBroken && link.breaksAnchor ? ' but missing anchor' : ''}"
        ')');
    if (link.destination.isRedirected) {
      print('  - redirect path:');
      var currentUrl = link.destination.url;
      for (final redirect in link.destination.redirects) {
        print('    - $currentUrl (${redirect.statusCode})');
        currentUrl = redirect.url;
      }
      print('    - $currentUrl (${link.destination.statusCode})');
    }
  }
  print('');
}

String _buildTagSummary(Link link) {
  var tag = '';
  if (link.origin.tagName == 'a') {
    const maxLength = 10;
    final text = link.origin.text.replaceAll('\n', ' ').trim();
    final length = text.length;
    if (length > 0) {
      if (length <= maxLength) {
        tag = "'$text' ";
      } else {
        tag = "'${text.substring(0, min(length, maxLength - 2))}..' ";
      }
    }
  } else if (link.origin.uri.path.endsWith('.css') &&
      link.origin.tagName == 'url') {
    tag = 'url(...) ';
  } else {
    tag = '<${link.origin.tagName}> ';
  }
  return tag;
}
