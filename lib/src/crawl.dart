library linkcheck.crawl;

import 'dart:async';
import 'dart:collection';
import 'dart:io' show Stdout;

import 'package:console/console.dart';

import 'destination.dart';
import 'link.dart';
import 'package:linkcheck/src/parsers/url_skipper.dart';
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
    UrlSkipper skipper,
    bool verbose,
    bool ansiTerm,
    Stream<dynamic> stopSignal,
    Stdout stdout) async {
  // Redirect output to injected [stdout] for better testing.
  void print(Object message) => stdout.writeln(message);

  Cursor cursor;
  TextPen pen;
  if (ansiTerm) {
    Console.init();
    cursor = Cursor();
    pen = TextPen();
  }

  if (verbose) {
    print("Crawl will start on the following URLs: $seeds");
    print("Crawl will check pages only on URLs satisfying: $hostGlobs");
    print("Crawl will skip links that match patterns: $skipper");
  }

  List<UriGlob> uriGlobs = hostGlobs.map((glob) => UriGlob(glob)).toList();

  // Maps from URLs (without fragment) to where their corresponding destination
  // lives.
  Map<String, Bin> bin = <String, Bin>{};

  // The queue of destinations that haven't been tried yet. Destinations in
  // the front of the queue take precedence.
  Queue<Destination> open = Queue<Destination>.from(seeds
      .map((uri) => Destination(uri)
        ..isSeed = true
        ..isSource = true
        ..isExternal = false)
      .toSet());
  open.forEach((destination) => bin[destination.url] = Bin.open);

  // Queue for the external destinations.
  Queue<Destination> openExternal = Queue<Destination>();

  Set<Destination> inProgress = <Destination>{};

  // The set of destinations that have been tried.
  Set<Destination> closed = <Destination>{};

  // Servers we are connecting to.
  Map<String, ServerInfo> servers = <String, ServerInfo>{};
  Queue<String> unknownServers = Queue<String>();
  Set<String> serversInProgress = <String>{};
  seeds.map((uri) => uri.authority).toSet().forEach((String host) {
    servers[host] = ServerInfo(host);
    unknownServers.add(host);
  });

  if (verbose) {
    print("Crawl will check the following servers (and their robots.txt) "
        "first: $unknownServers");
  }

  // Crate the links Set.
  Set<Link> links = <Link>{};

  int threads;
  if (shouldCheckExternal ||
      seeds.any(
          (seed) => seed.host != 'localhost' && seed.host != '127.0.0.1')) {
    threads = defaultThreads;
  } else {
    threads = localhostOnlyThreads;
  }
  if (verbose) print("Using $threads threads.");

  Pool pool = Pool(threads, hostGlobs);
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

  var allDone = Completer<Null>();

  // Respond to Ctrl-C
  StreamSubscription stopSignalSubscription;
  stopSignalSubscription = stopSignal.listen((dynamic _) async {
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
    await stopSignalSubscription.cancel();
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
    List<Destination> destinationsToRemove = <Destination>[];

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
        .putIfAbsent(result.host, () => ServerInfo(result.host))
        .updateFromServerCheck(result);
    if (verbose) {
      print("Server check of ${result.host} complete.");
    }

    if (verbose) {
      count++;
      print("Server check for ${result.host} complete: "
          "${result.didNotConnect ? 'didn\'t connect' : 'connected'}, "
          "${result.robotsTxtContents.isEmpty ? 'no robots.txt' : 'robots.txt found'}.");
    } else {
      if (ansiTerm) {
        cursor.moveLeft(count.toString().length);
        count++;
        cursor.write(count.toString());
      } else {
        count++;
      }
    }

    sendNewJobs();
  });

  // Respond to fetch results from a Worker
  pool.fetchResults.listen((FetchResults result) {
    assert(bin[result.checked.url] == Bin.inProgress);

    // Find the destination this result is referring to.
    var destinations = inProgress
        .where((dest) => dest.url == result.checked.url)
        .toList(growable: false);
    if (destinations.isEmpty) {
      if (verbose) {
        print("WARNING: Received result for a destination that isn't in "
            "the inProgress set: ${result.toMap()}");
        var isInOpen =
            open.where((dest) => dest.url == result.checked.url).isNotEmpty;
        var isInOpenExternal = openExternal
            .where((dest) => dest.url == result.checked.url)
            .isNotEmpty;
        var isInClosed =
            closed.where((dest) => dest.url == result.checked.url).isNotEmpty;
        print("- the url is in open: $isInOpen; "
            "in open external: $isInOpenExternal, in closed: $isInClosed");
      }
      return;
    } else if (destinations.length > 1) {
      if (verbose) {
        print("WARNING: Received result for a url (${result.checked.url} "
            "that matches several objects in the inProgress set: "
            "$destinations");
      }
      return;
    }
    var checked = destinations.single;

    inProgress.remove(checked);
    checked.updateFromResult(result.checked);

    if (verbose) {
      count++;
      print("Done checking: $checked (${checked.statusDescription}) "
          "=> ${result?.links?.length ?? 0} links");
      if (checked.isBroken) {
        print("- BROKEN");
      }
    } else {
      if (ansiTerm) {
        cursor.moveLeft(count.toString().length);
        count++;
        cursor.write(count.toString());
      } else {
        count++;
      }
    }

    closed.add(checked);
    bin[checked.url] = Bin.closed;

    var newDestinations = <Destination>{};

    // Add links' destinations to [newDestinations] if they haven't been
    // seen before.
    for (var link in result.links) {
      // Mark links as skipped first.
      if (skipper.skips(link.destinationUrlWithFragment)) {
        link.wasSkipped = true;
        if (verbose) {
          print("- will not be checking: ${link.destination} - "
              "${skipper.explain(link.destinationUrlWithFragment)}");
        }
        continue;
      }

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
          continue;
        }

        if (verbose) {
          print("- completely new destination: ${link.destination}");
        }

        newDestinations.add(link.destination);
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

      // Making sure this is set. The next (wasSkipped) section could
      // short-circuit this loop so we have to assign to isExternal here
      // while we have the chance.
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

      // The URL is external and wasn't skipped. We'll find out whether to
      // check it according to the [shouldCheckExternal] option.
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
        .where((destination) => !destination.isUnsupportedScheme)
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

  if (verbose) {
    print("All jobs are done or user pressed Ctrl-C");
  }

  await stopSignalSubscription.cancel();

  if (verbose) {
    print("Deduping destinations");
  }

  // Fix links (dedupe destinations).
  var urlMap = Map<String, Destination>.fromIterable(closed,
      key: (Object dest) => (dest as Destination).url);
  for (var link in links) {
    var canonical = urlMap[link.destination.url];
    // Note: If it wasn't for the posibility to SIGINT the process, we could
    // assert there is exactly one Destination per URL. There might not be,
    // though.
    if (canonical != null) {
      link.destination = canonical;
    }
  }

  if (verbose) {
    print("Closing the isolate pool");
  }

  if (!pool.isShuttingDown) {
    await pool.close();
  }

  assert(open.isEmpty);
  assert(closed.every((destination) =>
      destination.wasTried ||
      destination.isUnsupportedScheme ||
      (destination.isExternal && !shouldCheckExternal) ||
      destination.isUnsupportedScheme ||
      destination.wasDeniedByRobotsTxt));

  if (verbose) {
    print("Broken links");
    links.where((link) => link.destination.isBroken).forEach(print);
  }

  return CrawlResult(links, closed);
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
