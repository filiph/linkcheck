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
  final List<Worker> _workers;

  late Timer _healthCheckTimer;

  final Map<Worker, DateTime> _lastJobPosted = <Worker, DateTime>{};
  final Set<String> _hostGlobs;

  final StreamController<FetchResults> _fetchResultsSink =
      StreamController<FetchResults>();

  late final Stream<FetchResults> fetchResults = _fetchResultsSink.stream;

  final StreamController<String> _messagesSink = StreamController<String>();

  late final Stream<String> messages = _messagesSink.stream;

  final StreamController<ServerInfoUpdate> _serverCheckSink =
      StreamController<ServerInfoUpdate>();

  late final Stream<ServerInfoUpdate> serverCheckResults =
      _serverCheckSink.stream;

  bool _finished = false;

  Pool(this.count, this._hostGlobs)
      : _workers =
            List<Worker>.generate(count, (i) => Worker('$i'), growable: false);

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
    final worker = pickWorker();
    _lastJobPosted[worker] = DateTime.now();
    worker.destinationToCheck = destination;
    Timer(delay, () {
      if (_isShuttingDown) return;
      worker.sink
          .add(WorkerTask(verb: WorkerVerb.checkPage, data: destination));
    });
    return worker;
  }

  /// Starts a job to send request for /robots.txt on the server.
  Worker checkServer(String host) {
    final worker = pickWorker();
    worker.sink.add(WorkerTask(verb: WorkerVerb.checkServer, data: host));
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
    for (final worker in _workers) {
      if (worker.spawned && worker.idle) return worker;
    }
    throw StateError('Attempt to use Pool when all workers are busy. '
        'Please make sure to wait until Pool.allWorking is false.');
  }

  Future<void> spawn() async {
    await Future.wait(_workers.map((worker) => worker.spawn()));
    for (final worker in _workers) {
      worker.stream.listen((WorkerTask message) {
        switch (message.verb) {
          case WorkerVerb.checkPageDone:
            final fetchResults = message.data as FetchResults;
            _fetchResultsSink.add(fetchResults);
            worker.destinationToCheck = null;
          case WorkerVerb.checkServerDone:
            final serverUpdateResult = message.data as ServerInfoUpdate;
            _serverCheckSink.add(serverUpdateResult);
            worker.serverToCheck = null;
          case WorkerVerb.infoFromWorker:
            _messagesSink.add(message.data as String);
          default:
            throw StateError('Unrecognized verb from Worker: '
                '${message.verb}');
        }
      });
    }
    _addHostGlobs();

    _healthCheckTimer = Timer.periodic(healthCheckFrequency, (_) async {
      if (_isShuttingDown) return;
      final now = DateTime.now();
      for (var i = 0; i < _workers.length; i++) {
        final worker = _workers[i];
        final lastJobPostedWorker = _lastJobPosted[worker];
        if (!worker.idle &&
            !worker.isKilled &&
            lastJobPostedWorker != null &&
            now.difference(lastJobPostedWorker) > workerTimeout) {
          _messagesSink.add('Killing unresponsive $worker');
          final destination = worker.destinationToCheck;
          final server = worker.serverToCheck;

          _lastJobPosted.remove(worker);
          final newWorker = Worker('$i');
          _workers[i] = newWorker;

          if (destination != null) {
            // Only notify about the failed destination when the old
            // worker is gone. Otherwise, crawl could fail to wrap up, thinking
            // that one Worker is still working.
            final checked = DestinationResult.fromDestination(destination,
                didNotConnect: true);
            final result = FetchResults(checked);
            _fetchResultsSink.add(result);
          }

          if (server != null) {
            final result = ServerInfoUpdate.didNotConnect(server);
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
    for (final worker in _workers) {
      worker.sink.add(WorkerTask(
          verb: WorkerVerb.addHostGlob,
          data: _hostGlobs.toList(growable: false)));
    }
  }
}
