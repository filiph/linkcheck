library linkcheck.check;

import 'dart:async';
import 'dart:collection';

import 'package:console/console.dart';

import 'destination.dart';
import 'link.dart';
import 'uri_glob.dart';
import 'worker/worker.dart';

const threads =
    8; // TODO: add threads when there are non-localhost sites: 8 non-local is best, 4 local is best

/// Specifies where a URI (without fragment) can be found. Used by a hashmap
/// in [crawl].
enum Bin { open, openExternal, inProgress, closed }

Future<List<Link>> crawl(List<Uri> seeds, Set<String> hostGlobs,
    bool shouldCheckExternal, bool verbose) async {
  Console.init();
  var cursor = new Cursor();

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

  Pool pool = new Pool(threads, hostGlobs);
  await pool.spawn();

  int count = 0;
  if (!verbose) {
    cursor.write("Crawling sources: $count");
  }

  // TODO:
  // - --cache for creating a .linkcheck.cache file
  // - hashmap with info on domains - allows HEAD, breaks connections, etc.
  // - open+close has a hashmap (uriWithoutFragment => Destination) for faster checking

  var allDone = new Completer<Null>();

  pool.fetchResults.listen((FetchResults result) {
    assert(bin[result.checked.url] == Bin.inProgress);
    var checked =
        inProgress.singleWhere((dest) => dest.url == result.checked.url);
    inProgress.remove(checked);
    checked.updateFromResult(result.checked);

    if (verbose) {
      count += 1;
      print("Done checking: $checked (${checked.statusDescription}) "
          "=> ${result.links.length} links");
      if (checked.isBroken) {
        print("- BROKEN");
      }
    } else {
      cursor.moveLeft(count.toString().length);
      count += 1;
      cursor.write(count.toString());
    }

    closed.add(checked);
    bin[checked.url] = Bin.closed;

    var newDestinations = new Set<Destination>();

    // Dedupe destinations in links. Add their destinations to [newDestinations]
    // if they haven't been seen before.
    for (var link in result.links) {
      var location = bin[link.destination.url];
      if (location == null) {
        // Completely new destination.
        assert(open.where((d) => d.url == link.destination.url).isEmpty);
        assert(
            openExternal.where((d) => d.url == link.destination.url).isEmpty);
        assert(inProgress.where((d) => d.url == link.destination.url).isEmpty);
        assert(closed.where((d) => d.url == link.destination.url).isEmpty);
        newDestinations.add(link.destination);
        continue;
      }

      Iterable<Destination> iterable;
      switch (location) {
        case Bin.open:
          iterable = open;
          break;
        case Bin.openExternal:
          iterable = openExternal;
          break;
        case Bin.inProgress:
          iterable = inProgress;
          break;
        case Bin.closed:
          iterable = closed;
          break;
      }
      link.destination =
          iterable.singleWhere((d) => d.url == link.destination.url);
    }

    links.addAll(result.links);

    for (var destination in newDestinations) {
      destination.isExternal =
          !uriGlobs.any((glob) => glob.matches(destination.uri));

      if (destination.isExternal) {
        if (!shouldCheckExternal) {
          // Don't check external destinations.
          closed.add(destination);
          bin[destination.url] = Bin.closed;
          continue;
        } else {
          openExternal.add(destination);
          bin[destination.url] = Bin.openExternal;
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
      if (verbose) {
        print("About to add: ${open.first} to ${pool.pickWorker()}");
      }
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
      pool.check(destination);
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

  // TODO: (optionally) check anchors

  pool.close();

  assert(open.isEmpty);
  assert(closed.every((destination) =>
      destination.wasTried ||
      (destination.isExternal && !shouldCheckExternal)));

//  for (var d in closed.where((d) => d.isSource && !d.isExternal).map((dest)=> dest.uriWithoutFragment).toSet()) {
//    print(d);
//  }

  if (verbose) {
    links.where((link) => link.destination.isBroken).forEach(print);
    print("All was tried");
    print(links.every((link) => link.destination.wasTried));
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
