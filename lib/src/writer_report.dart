library linkcheck.writer_report;

import 'dart:math' show min;

import 'link.dart';

/// Writes the reports from the perspective of a website writer - which pages
/// reference broken links.
void reportForWriters(List<Link> links) {
  List<Link> broken = links
      .where((link) =>
          link.destination.wasTried &&
          (link.destination.isBroken || !link.satisfiesFragment))
      .toList(growable: false);

  List<Uri> sourceUris =
      broken.map((link) => link.origin.uri).toSet().toList(growable: false);
  sourceUris.sort((a, b) => a.toString().compareTo(b.toString()));

  for (var uri in sourceUris) {
    print(uri);

    var links = broken.where((link) => link.origin.uri == uri);
    for (var link in links) {
      String tag = _buildTagSummary(link);
      print("- (${link.origin.span.start.line}"
          ":${link.origin.span.start.column}) "
          "$tag"
          "=> ${link.destination.uri}"
          "${link.fragment == null
              ? ''
              : '#' + link.fragment} "
          "(${link.destination.statusDescription}"
          "${link.satisfiesFragment ? '' : ' but missing anchor'})");
      if (link.destination.isRedirected) {
        print("  - redirect path:");
        String current = link.destination.url;
        for (var redirect in link.destination.redirects) {
          print("    - $current (${redirect.statusCode})");
          current = redirect.url;
        }
        print("    - $current (${link.destination.statusCode})");
      }
    }
    print("");
  }
}

String _buildTagSummary(Link link) {
  String tag = "";
  if (link.origin.tagName == 'a') {
    const maxLength = 10;
    var text = link.origin.text;
    int length = text.length;
    if (length > 0) {
      if (length <= maxLength) {
        tag = "'$text' ";
      } else {
        tag = "'${text.substring(0, min(length, maxLength - 2))}..' ";
      }
    }
  } else if (link.origin.uri.path.endsWith(".css") &&
      link.origin.tagName == "url") {
    tag = "url(...) ";
  } else {
    tag = "<${link.origin.tagName}> ";
  }
  return tag;
}
