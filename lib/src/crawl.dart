library linkcheck.crawl;

import 'dart:async';
import 'dart:collection';

import 'package:console/console.dart';

import 'destination.dart';
import 'link.dart';
import 'uri_glob.dart';
import 'server_info.dart';
import 'worker/pool.dart';
import 'worker/fetch_results.dart';

/// Number of isolates to create by default.
const defaultThreads = 8;

/// Number of isolates to create when all we check are localhost sources.
const localhostOnlyThreads = 4;

/// Specifies where a URI (without fragment) can be found. Used by a hashmap
/// in [crawl].
enum Bin { open, openExternal, inProgress, closed }

Future<CrawlResult> crawl(
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
        ..isSeed = true
        ..isSource = true
        ..isExternal = false));
  open.forEach((destination) => bin[destination.url] = Bin.open);

  // Queue for the external destinations.
  Queue<Destination> openExternal = new Queue<Destination>();

  Set<Destination> inProgress = new Set<Destination>();

  // The set of destinations that have been tried.
  Set<Destination> closed = new Set<Destination>();

  // Servers we are connecting to.
  Map<String, ServerInfo> servers = new Map<String, ServerInfo>();
  Queue<String> unknownServers = new Queue<String>();
  Set<String> serversInProgress = new Set<String>();
  seeds.map((uri) => uri.authority).toSet().forEach((String host) {
    servers[host] = new ServerInfo(host);
    unknownServers.add(host);
  });

  if (verbose) {
    print("Crawl will check the following servers (and their robots.txt) "
        "first: $unknownServers");
  }

  // Crate the links Set.
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
  // -v for version
  // -d for debug (verbose now)
  // - --cache for creating a .linkcheck.cache file

  var allDone = new Completer<Null>();

  // Respond to Ctrl-C
  StreamSubscription stopSignalSubscription;
  stopSignalSubscription = stopSignal.listen((_) async {
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
    await pool.close();
    allDone.complete();
    stopSignalSubscription.cancel();
  });

  /// Creates new jobs and sends them to the Pool of Workers, if able.
  void sendNewJobs() {
    while (unknownServers.isNotEmpty && pool.anyIdle) {
      var host = unknownServers.removeFirst();
      pool.checkServer(host);
      serversInProgress.add(host);
      if (verbose) {
        print("Checking robots.txt and availability of server: $host");
      }
    }

    bool _serverIsKnown(Destination destination) =>
        servers.keys.contains(destination.uri.authority);

    Iterable<Destination> availableDestinations =
        _zip(open.where(_serverIsKnown), openExternal.where(_serverIsKnown));

    // In order not to touch the underlying iterables, we keep track
    // of the destinations we want to remove.
    List<Destination> destinationsToRemove = new List<Destination>();

    for (var destination in availableDestinations) {
      if (pool.allBusy) break;

      destinationsToRemove.add(destination);

      String host = destination.uri.authority;
      ServerInfo server = servers[host];
      if (server.hasNotConnected) {
        destination.didNotConnect = true;
        closed.add(destination);
        bin[destination.url] = Bin.closed;
        if (verbose) {
          print("Automatically failing $destination because server $host has "
              "failed before.");
        }
        continue;
      }

      if (server.bouncer != null &&
          !server.bouncer.allows(destination.uri.path)) {
        destination.wasDeniedByRobotsTxt = true;
        closed.add(destination);
        bin[destination.url] = Bin.closed;
        if (verbose) {
          print("Skipping $destination because of robots.txt at $host.");
        }
        continue;
      }

      var delay = server.getThrottlingDuration();
      if (delay > ServerInfo.minimumDelay) {
        // Some other worker is already waiting with a checkPage request.
        // Let's try and see if we have more interesting options down the
        // iterable. Do not remove it.
        destinationsToRemove.remove(destination);
        continue;
      }

      var worker = pool.checkPage(destination, delay);
      server.markRequestStart(delay);
      if (verbose) {
        print("Added: $destination to $worker with "
            "${delay.inMilliseconds}ms delay");
      }
      inProgress.add(destination);
      bin[destination.url] = Bin.inProgress;
    }

    for (var destination in destinationsToRemove) {
      open.remove(destination);
      openExternal.remove(destination);
    }

    if (unknownServers.isEmpty &&
        open.isEmpty &&
        openExternal.isEmpty &&
        pool.allIdle) {
      allDone.complete();
      return;
    }
  }

  // Respond to new server info from Worker
  pool.serverCheckResults.listen((ServerInfoUpdate result) {
    serversInProgress.remove(result.host);
    servers
        .putIfAbsent(result.host, () => new ServerInfo(result.host))
        .updateFromServerCheck(result);
    if (verbose) {
      print("Server check of ${result.host} complete.");
    }

    if (verbose) {
      count += 1;
      print("Server check for ${result.host} complete: "
          "${result.didNotConnect ? 'didn\'t connect' : 'connected'}, "
          "${result.robotsTxtContents.isEmpty
              ? 'no robots.txt'
              : 'robots.txt found'}.");
    } else {
      if (ansiTerm) {
        cursor.moveLeft(count.toString().length);
        count += 1;
        cursor.write(count.toString());
      } else {
        count += 1;
      }
    }

    sendNewJobs();
  });

  // Respond to fetch results from a Worker
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

    // Do any destinations have different hosts? Add them to unknownServers.
    Iterable<String> newHosts = newDestinations
        .where((destination) => !destination.isInvalid)
        .where((destination) => shouldCheckExternal || !destination.isExternal)
        .map((destination) => destination.uri.authority)
        .where((String host) =>
            !unknownServers.contains(host) &&
            !serversInProgress.contains(host) &&
            !servers.keys.contains(host));
    unknownServers.addAll(newHosts);

    // Continue sending new jobs.
    sendNewJobs();
  });

  if (verbose) {
    pool.messages.listen((message) {
      print(message);
    });
  }

  // Start the crawl. First, check servers for robots.txt etc.
  sendNewJobs();

  // This will suspend until after everything is done (or user presses Ctrl-C).
  await allDone.future;

  stopSignalSubscription.cancel();

  // Fix links (dedupe destinations).
  for (var link in links) {
    // If it wasn't for the posibility to SIGINT the process, we could assume
    // there is exactly one [canonical]. Alas, we need to make sure.
    var canonical = closed.where((d) => d.url == link.destination.url).toList();
    if (canonical.length == 1) {
      link.destination = canonical.single;
    }
  }

  if (!pool.isShuttingDown) {
    await pool.close();
  }

  assert(open.isEmpty);
  assert(closed.every((destination) =>
      destination.wasTried ||
      (destination.isExternal && !shouldCheckExternal) ||
      destination.isUnsupportedScheme));

  if (verbose) {
    print("Broken links");
    links.where((link) => link.destination.isBroken).forEach(print);
  }

  return new CrawlResult(links, closed);
}

class CrawlResult {
  final Set<Link> links;
  final Set<Destination> destinations;
  const CrawlResult(this.links, this.destinations);
}

/// Zips two iterables of [Destination] into one.
///
/// Alternates between [a] and [b]. When one of the iterables is depleted,
/// the second iterable's remaining values will be yielded.
Iterable<Destination> _zip(
    Iterable<Destination> a, Iterable<Destination> b) sync* {
  var aIterator = a.iterator;
  var bIterator = b.iterator;

  while (true) {
    bool aExists = aIterator.moveNext();
    bool bExists = bIterator.moveNext();
    if (!aExists && !bExists) break;

    if (aExists) yield aIterator.current;
    if (bExists) yield bIterator.current;
  }
}
