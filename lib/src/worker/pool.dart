library linkcheck.pool;

import 'dart:async';

import '../destination.dart';
import 'fetch_results.dart';
import 'worker.dart';

class Pool {
  static const workerTimeout = const Duration(seconds: 10);
  static const healthCheckFrequency = const Duration(seconds: 1);

  /// The number of threads.
  final int count;

  List<Worker> _workers;

  Timer _healthCheckTimer;
  Map<Worker, DateTime> _lastJobPosted = new Map<Worker, DateTime>();

  final Set<String> _hostGlobs;

  StreamController<FetchResults> _fetchResultsSink =
      new StreamController<FetchResults>();
  Stream<FetchResults> fetchResults;

  StreamController<String> _messagesSink = new StreamController<String>();
  Stream<String> messages;

  Pool(this.count, this._hostGlobs) {
    fetchResults = _fetchResultsSink.stream;
    messages = _messagesSink.stream;
  }

  bool get allIdle => _workers.every((worker) => worker.idle);

  bool get allWorking => _workers.every((worker) => !worker.idle);

  void check(Destination destination) {
    var worker = pickWorker();
    worker.sink.add({verbKey: checkVerb, dataKey: destination.toMap()});
    worker.destinationToCheck = destination;
    _lastJobPosted[worker] = new DateTime.now();
  }

  Future<Null> close() async {
    _healthCheckTimer.cancel();
    await Future.wait(_workers.map((worker) async {
      worker.sink.add(dieMessage);
      await worker.sink.close();
    }));
  }

  /// Finds the worker with the least amount of jobs.
  Worker pickWorker() {
    for (var worker in _workers) {
      if (worker.spawned && worker.idle) return worker;
    }
    throw new StateError("Attempt to use Pool when all workers are busy. "
        "Please make sure to wait until Pool.allWorking is false.");
  }

  Future<Null> spawn() async {
    _workers =
        new List<Worker>.generate(count, (i) => new Worker()..name = '$i');
    await Future.wait(_workers.map((worker) => worker.spawn()));
    _workers.forEach((worker) => worker.stream.listen((Map message) {
          switch (message[verbKey]) {
            case checkDoneVerb:
              var result = new FetchResults.fromMap(
                  message[dataKey] as Map<String, Object>);
              _fetchResultsSink.add(result);
              worker.destinationToCheck = null;
              return;
            case infoFromWorkerVerb:
              _messagesSink.add(message[dataKey]);
              return;
            default:
              throw new StateError("Unrecognized verb from Worker: "
                  "${message[verbKey]}");
          }
        }));
    _addHostGlobs();

    _healthCheckTimer = new Timer.periodic(healthCheckFrequency, (_) async {
      var now = new DateTime.now();
      for (int i = 0; i < _workers.length; i++) {
        var worker = _workers[i];
        if (!worker.idle &&
            now.difference(_lastJobPosted[worker]) > workerTimeout) {
          _messagesSink.add("Killing unresponsive $worker");
          var destination = worker.destinationToCheck;
          var checked = new DestinationResult.fromDestination(destination);
          checked.didNotConnect = true;
          var result = new FetchResults(checked, null);
          _fetchResultsSink.add(result);
          _killUnresponsive(worker);
          var newWorker = new Worker()..name = '$i';
          _workers[i] = newWorker;
          await newWorker.spawn();
        }
      }
    });
  }

  void _killUnresponsive(Worker worker) {
    worker.sink.add(dieMessage);
    worker.sink.close();
    _lastJobPosted.remove(worker);
  }

  /// Sends host globs (e.g. http://example.com/**) to all the workers.
  void _addHostGlobs() {
    for (var worker in _workers) {
      worker.sink.add({verbKey: addHostGlobVerb, dataKey: _hostGlobs.toList()});
    }
  }
}
