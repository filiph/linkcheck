import 'dart:async';

import '../destination.dart';
import '../server_info.dart';
import 'fetch_results.dart';
import 'worker.dart';

class Pool {
  /// How much time before we kill a [Worker].
  ///
  /// This should give it enough time for the HttpClient [fetchTimeout]
  /// plus buffer for actual Dart code.
  static final workerTimeout = fetchTimeout + const Duration(milliseconds: 500);
  static const healthCheckFrequency = Duration(seconds: 1);

  /// The number of threads.
  final int count;

  bool _isShuttingDown = false;
  List<Worker> _workers;

  Timer _healthCheckTimer;

  final Map<Worker, DateTime> _lastJobPosted = <Worker, DateTime>{};
  final Set<String> _hostGlobs;

  final StreamController<FetchResults> _fetchResultsSink =
      StreamController<FetchResults>();

  late final Stream<FetchResults> fetchResults;

  final StreamController<String> _messagesSink = StreamController<String>();

  late final Stream<String> messages;

  final StreamController<ServerInfoUpdate> _serverCheckSink =
      StreamController<ServerInfoUpdate>();

  late final Stream<ServerInfoUpdate> serverCheckResults;

  bool _finished = false;

  Pool(this.count, this._hostGlobs) {
    fetchResults = _fetchResultsSink.stream;
    messages = _messagesSink.stream;
    serverCheckResults = _serverCheckSink.stream;
  }

  /// Returns true if all workers are either waiting for a job or not really
  /// alive (not spawned yet, or already killed).
  bool get allIdle => _workers
      .every((worker) => worker.idle || !worker.spawned || worker.isKilled);

  bool get anyIdle => _workers.any((worker) => worker.idle);

  bool get allBusy => !anyIdle;

  bool get finished => _finished;

  bool get isShuttingDown => _isShuttingDown;

  /// Asks a worker to check the given [destination]. Waits [delay] before
  /// doing so.
  Worker checkPage(Destination destination, Duration delay) {
    var worker = pickWorker();
    _lastJobPosted[worker] = DateTime.now();
    worker.destinationToCheck = destination;
    Timer(delay, () {
      if (_isShuttingDown) return;
      worker.sink.add({verbKey: checkPageVerb, dataKey: destination.toMap()});
    });
    return worker;
  }

  /// Starts a job to send request for /robots.txt on the server.
  Worker checkServer(String host) {
    var worker = pickWorker();
    worker.sink.add({verbKey: checkServerVerb, dataKey: host});
    worker.serverToCheck = host;
    _lastJobPosted[worker] = DateTime.now();
    return worker;
  }

  Future<void> close() async {
    _isShuttingDown = true;
    _healthCheckTimer.cancel();
    await Future.wait(_workers.map((worker) async {
      if (!worker.spawned || worker.isKilled) return;
      await worker.kill();
    }));
    _finished = true;
  }

  /// Finds the worker with the least amount of jobs.
  Worker pickWorker() {
    for (var worker in _workers) {
      if (worker.spawned && worker.idle) return worker;
    }
    throw StateError("Attempt to use Pool when all workers are busy. "
        "Please make sure to wait until Pool.allWorking is false.");
  }

  Future<void> spawn() async {
    _workers = List<Worker>.generate(count, (i) => Worker()..name = '$i');
    await Future.wait(_workers.map((worker) => worker.spawn()));
    for (var worker in _workers) {
      worker.stream.listen((Map<dynamic, dynamic> message) {
        switch (message[verbKey] as String) {
          case checkPageDoneVerb:
            var result =
                FetchResults.fromMap(message[dataKey] as Map<String, Object>);
            _fetchResultsSink.add(result);
            worker.destinationToCheck = null;
            break;
          case checkServerDoneVerb:
            var result = ServerInfoUpdate.fromMap(
                message[dataKey] as Map<String, Object>);
            _serverCheckSink.add(result);
            worker.serverToCheck = null;
            break;
          case infoFromWorkerVerb:
            _messagesSink.add(message[dataKey] as String);
            break;
          default:
            throw StateError("Unrecognized verb from Worker: "
                "${message[verbKey]}");
        }
      });
    }
    _addHostGlobs();

    _healthCheckTimer = Timer.periodic(healthCheckFrequency, (_) async {
      if (_isShuttingDown) return;
      var now = DateTime.now();
      for (int i = 0; i < _workers.length; i++) {
        var worker = _workers[i];
        var lastJobPostedWorker = _lastJobPosted[worker];
        if (!worker.idle &&
            !worker.isKilled &&
            lastJobPostedWorker != null &&
            now.difference(lastJobPostedWorker) > workerTimeout) {
          _messagesSink.add("Killing unresponsive $worker");
          var destination = worker.destinationToCheck;
          var server = worker.serverToCheck;

          _lastJobPosted.remove(worker);
          var newWorker = Worker()..name = '$i';
          _workers[i] = newWorker;

          if (destination != null) {
            // Only notify about the failed destination when the old
            // worker is gone. Otherwise, crawl could fail to wrap up, thinking
            // that one Worker is still working.
            var checked = DestinationResult.fromDestination(destination);
            checked.didNotConnect = true;
            var result = FetchResults(checked, const []);
            _fetchResultsSink.add(result);
          }

          if (server != null) {
            var result = ServerInfoUpdate(server);
            result.didNotConnect = true;
            _serverCheckSink.add(result);
          }

          await newWorker.spawn();
          if (_isShuttingDown) {
            // The pool has been closed in the time it took to spawn this
            // worker.
            await newWorker.kill();
          }
          await worker.kill();
        }
      }
    });
  }

  /// Sends host globs (e.g. http://example.com/**) to all the workers.
  void _addHostGlobs() {
    for (var worker in _workers) {
      worker.sink.add({verbKey: addHostGlobVerb, dataKey: _hostGlobs.toList()});
    }
  }
}
