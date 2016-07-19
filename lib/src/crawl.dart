library linkcheck.check;

import 'dart:async';
import 'dart:collection';
import 'dart:io' hide Link;

import 'package:console/console.dart';

import 'destination.dart';
import 'link.dart';
import 'uri_glob.dart';
import 'worker/worker.dart';

const threads = 4;

Future<List<Link>> crawl(List<Uri> seeds, Set<String> hostGlobs,
    bool shouldCheckExternal, bool verbose) async {
  Console.init();
  var cursor = new Cursor();

  if (verbose) {
    print("Crawl will start on the following URLs: $seeds");
    print("Crawl will check pages only on URLs satisfying: $hostGlobs");
  }

  List<UriGlob> uriGlobs = hostGlobs.map((glob) => new UriGlob(glob)).toList();

  // The queue of destinations that haven't been tried yet. Destinations in
  // the front of the queue take precedence.
  Queue<Destination> open = new Queue<Destination>.from(
      seeds.map((uri) => new Destination(uri)..isSource = true));

  // The set of destinations that have been tried.
  Set<Destination> closed = new Set<Destination>();

  // Set of destinations with the same uriWithoutFragment as any destination in
  // [open] or [closed]. No need to fetch them, too.
  Set<Destination> duplicates = new Set<Destination>();

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
    if (verbose) {
      print("Done checking: ${result.checked}");
    } else {
      cursor.moveLeft(count.toString().length);
      count += 1;
      cursor.write(count.toString());
    }
    closed.add(result.checked);
    _updateEquivalents(result.checked, open, closed);

    for (var link in result.links) {
      // Dedupe destinations.
      for (var destination in closed) {
        if (link.destination == destination) {
          link.destination = destination;
          break;
        }
      }
      // TODO: don't run if already deduped in closed (destination can only be in closed OR in open, never both)
      for (var destination in open) {
        if (link.destination == destination) {
          link.destination = destination;
          break;
        }
      }
      for (var destination in pool.inProgress) {
        if (link.destination == destination) {
          link.destination = destination;
          break;
        }
      }
      for (var destination in duplicates) {
        if (link.destination == destination) {
          link.destination = destination;
          break;
        }
      }
    }
    links.addAll(result.links);
    var destinations = result.links.map((link) => link.destination).toSet();
    for (var destination in destinations) {
      destination.isExternal =
          !uriGlobs.any((glob) => glob.matches(destination.uri));

      if (!closed.contains(destination) &&
          !pool.inProgress.contains(destination) &&
          !open.contains(destination)) {
        if (!shouldCheckExternal && destination.isExternal) {
          // Don't check external destinations.
          closed.add(destination);
          continue;
        }

        if (closed.any((other) =>
                other.uriWithoutFragment == destination.uriWithoutFragment) ||
            pool.inProgress.any((other) =>
                other.uriWithoutFragment == destination.uriWithoutFragment) ||
            open.any((other) =>
                other.uriWithoutFragment == destination.uriWithoutFragment)) {
          duplicates.add(destination);
          continue;
        }

        if (destination.isSource) {
          open.addFirst(destination);
        } else {
          open.addLast(destination);
        }
      }
    }

    while (open.isNotEmpty && !pool.allWorking) {
      if (verbose) {
        print("About to add: ${open.first} to ${pool.pickWorker()}");
      }
      pool.check(open.removeFirst());
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
  }

  await allDone.future;

  // TODO: (optionally) check anchors

  pool.close();

  assert(open.isEmpty);
  assert(closed.every((destination) =>
      destination.wasTried ||
      (destination.isExternal && !shouldCheckExternal)));

  // Re-add duplicates.
  duplicates.forEach((duplicate) => duplicate.updateFrom(closed.singleWhere(
      (other) => other.uriWithoutFragment == duplicate.uriWithoutFragment)));
  closed.addAll(duplicates);

  // TODO: return also closed?
  return links.toList(growable: false);
}

void _updateEquivalents(
    Destination current, Queue<Destination> open, Set<Destination> closed) {
  List<Destination> equivalents = _getEquivalents(current, open).toList();
  for (var other in equivalents) {
    other.updateFrom(current);
    open.remove(other);
    closed.add(other);
  }
}

/// Returns all destinations that share the same
/// [Destination.uriWithoutFragment] with [current].
Iterable<Destination> _getEquivalents(
        Destination current, Iterable<Destination> destinations) =>
    destinations.where((destination) =>
        destination.uriWithoutFragment == current.uriWithoutFragment &&
        destination != current);
