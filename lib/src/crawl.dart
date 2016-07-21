library linkcheck.crawl;

import 'dart:async';
import 'dart:collection';

import 'package:console/console.dart';

import 'destination.dart';
import 'link.dart';
import 'uri_glob.dart';
import 'worker/pool.dart';
import 'worker/fetch_results.dart';

/// Number of isolates to create by default.
const defaultThreads = 8;

/// Number of isolates to create when all we check are localhost sources.
const localhostOnlyThreads = 4;

/// Specifies where a URI (without fragment) can be found. Used by a hashmap
/// in [crawl].
enum Bin { open, openExternal, inProgress, closed }

Future<List<Link>> crawl(
    List<Uri> seeds,
    Set<String> hostGlobs,
    bool shouldCheckExternal,
    bool verbose,
    bool ansiTerm,
    Stream<dynamic> stopSignal) async {
  Cursor cursor;
  TextPen pen;
  if (ansiTerm) {
    Console.init();
    cursor = new Cursor();
    pen = new TextPen();
  }

  if (verbose) {
    print("Crawl will start on the following URLs: $seeds");
    print("Crawl will check pages only on URLs satisfying: $hostGlobs");
  }

  List<UriGlob> uriGlobs = hostGlobs.map((glob) => new UriGlob(glob)).toList();

  // Maps from URLs (without fragment) to where their corresponding destination
  // lives.
  Map<String, Bin> bin = new Map<String, Bin>();

  // The queue of destinations that haven't been tried yet. Destinations in
  // the front of the queue take precedence.
  Queue<Destination> open =
      new Queue<Destination>.from(seeds.map((uri) => new Destination(uri)
        ..isSource = true
        ..isExternal = false));
  open.forEach((destination) => bin[destination.url] = Bin.open);

  // Queue for the external destinations.
  Queue<Destination> openExternal = new Queue<Destination>();

  Set<Destination> inProgress = new Set<Destination>();

  // The set of destinations that have been tried.
  Set<Destination> closed = new Set<Destination>();

  // List of hosts that do not support HTTP HEAD requests.
  Set<String> headIncompatible = new Set<String>();

  // TODO: add hashmap with robots. Special case for localhost

  Set<Link> links = new Set<Link>();

  int threads;
  if (shouldCheckExternal || seeds.any((seed) => seed.host != 'localhost')) {
    threads = defaultThreads;
  } else {
    threads = localhostOnlyThreads;
  }
  if (verbose) print("Using $threads threads.");

  Pool pool = new Pool(threads, hostGlobs);
  await pool.spawn();

  int count = 0;
  if (!verbose) {
    if (ansiTerm) {
      cursor.write("Crawling: $count");
    } else {
      print("Crawling...");
    }
  }

  // TODO:
  // - --cache for creating a .linkcheck.cache file
  // - hashmap with info on domains - allows HEAD, breaks connections, etc.

  var allDone = new Completer<Null>();

  // Respond to Ctrl-C
  StreamSubscription stopSignalSubscription;
  stopSignalSubscription = stopSignal.listen((_) {
    if (ansiTerm) {
      pen
          .text("\n")
          .red()
          .text("Ctrl-C")
          .normal()
          .text(" Terminating crawl.")
          .print();
    } else {
      print("\nSIGINT: Terminating crawl");
    }
    pool.close();
    allDone.complete();
    stopSignalSubscription.cancel();
  });

  pool.fetchResults.listen((FetchResults result) {
    assert(bin[result.checked.url] == Bin.inProgress);
    var checked =
        inProgress.singleWhere((dest) => dest.url == result.checked.url);
    inProgress.remove(checked);
    checked.updateFromResult(result.checked);

    if (verbose) {
      count += 1;
      print("Done checking: $checked (${checked.statusDescription}) "
          "=> ${result?.links?.length ?? 0} links");
      if (checked.isBroken) {
        print("- BROKEN");
      }
    } else {
      if (ansiTerm) {
        cursor.moveLeft(count.toString().length);
        count += 1;
        cursor.write(count.toString());
      } else {
        count += 1;
      }
    }

    closed.add(checked);
    bin[checked.url] = Bin.closed;

    var newDestinations = new Set<Destination>();

    // Add links' destinations to [newDestinations] if they haven't been
    // seen before.
    for (var link in result.links) {
      if (bin[link.destination.url] == null) {
        // Completely new destination.
        assert(open.where((d) => d.url == link.destination.url).isEmpty);
        assert(
            openExternal.where((d) => d.url == link.destination.url).isEmpty);
        assert(inProgress.where((d) => d.url == link.destination.url).isEmpty);
        assert(closed.where((d) => d.url == link.destination.url).isEmpty);

        var alreadyOnCurrent = newDestinations.lookup(link.destination);
        if (alreadyOnCurrent != null) {
          if (verbose) {
            print("- destination: ${link.destination} already "
                "seen on this page");
          }
        } else {
          if (verbose) {
            print("- completely new destination: ${link.destination}");
          }
          newDestinations.add(link.destination);
        }
      }
    }

    links.addAll(result.links);

    for (var destination in newDestinations) {
      if (destination.isInvalid) {
        if (verbose) {
          print("Will not be checking: $destination - invalid url");
        }
        continue;
      }

      destination.isExternal =
          !uriGlobs.any((glob) => glob.matches(destination.uri));

      if (destination.isUnsupportedScheme) {
        // Don't check unsupported schemes (like mailto:).
        closed.add(destination);
        bin[destination.url] = Bin.closed;
        if (verbose) {
          print("Will not be checking: $destination - unsupported scheme");
        }
        continue;
      }

      if (destination.isExternal) {
        if (shouldCheckExternal) {
          openExternal.add(destination);
          bin[destination.url] = Bin.openExternal;
          continue;
        } else {
          // Don't check external destinations.
          closed.add(destination);
          bin[destination.url] = Bin.closed;
          if (verbose) {
            print("Will not be checking: $destination - external");
          }
          continue;
        }
      }

      if (destination.isSource) {
        open.addFirst(destination);
        bin[destination.url] = Bin.open;
      } else {
        open.addLast(destination);
        bin[destination.url] = Bin.open;
      }
    }

    while ((open.isNotEmpty || openExternal.isNotEmpty) && !pool.allWorking) {
      Destination destination;
      if (openExternal.isEmpty) {
        destination = open.removeFirst();
      } else if (open.isEmpty) {
        destination = openExternal.removeFirst();
      } else {
        // Alternate between internal and external.
        destination =
            count % 2 == 0 ? open.removeFirst() : openExternal.removeFirst();
      }
      var worker = pool.check(destination);
      if (verbose) {
        print("Added: $destination to $worker");
      }
      inProgress.add(destination);
      bin[destination.url] = Bin.inProgress;
    }

    if (open.isEmpty && pool.allIdle) {
      allDone.complete();
      return;
    }
  });

  if (verbose) {
    pool.messages.listen((message) {
      print(message);
    });
  }

  // Start the crawl.
  while (open.isNotEmpty && !pool.allWorking) {
    var seedDestination = open.removeFirst();
    pool.check(seedDestination);
    inProgress.add(seedDestination);
    bin[seedDestination.url] = Bin.inProgress;
  }

  await allDone.future;

  stopSignalSubscription.cancel();

  // Fix links (dedupe destinations).
  for (var link in links) {
    assert(bin[link.destination.url] == Bin.closed);

    // If it wasn't for the posibility to SIGINT the process, we could
    var canonical = closed.where((d) => d.url == link.destination.url).toList();
    if (canonical.length == 1) {
      link.destination = canonical.single;
    }
  }

  if (!pool.finished) pool.close();

  assert(open.isEmpty);
  assert(closed.every((destination) =>
      destination.wasTried ||
      (destination.isExternal && !shouldCheckExternal) ||
      destination.isUnsupportedScheme));

//  for (var d in closed.where((d) => d.isSource && !d.isExternal).map((dest)=> dest.uriWithoutFragment).toSet()) {
//    print(d);
//  }

  if (verbose) {
    print("Broken links");
    links.where((link) => link.destination.isBroken).forEach(print);
  }

  return links.toList(growable: false);
}

//void _updateEquivalents(
//    Destination current, Queue<Destination> open, Set<Destination> closed) {
//  List<Destination> equivalents = _getEquivalents(current, open).toList();
//  for (var other in equivalents) {
//    other.updateFrom(current);
//    open.remove(other);
//    closed.add(other);
//  }
//}
//
///// Returns all destinations that share the same
///// [Destination.uriWithoutFragment] with [current].
//Iterable<Destination> _getEquivalents(
//        Destination current, Iterable<Destination> destinations) =>
//    destinations.where((destination) =>
//        destination.uriWithoutFragment == current.uriWithoutFragment &&
//        destination != current);
