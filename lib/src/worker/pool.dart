library linkcheck.pool;
import 'dart:async';

import '../destination.dart';
import 'fetch_results.dart';
import 'worker.dart';


class Pool {
  /// The number of threads.
  final int count;

  List<Worker> _workers;

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
    worker.urlsToCheck.add(destination.url);
  }

  Future<Null> close() async {
    await Future.wait(_workers.map((worker) async {
      worker.sink.add(dieMessage);
      await worker.sink.close();
    }));
  }

  /// Finds the worker with the least amount of jobs.
  Worker pickWorker() {
    for (var worker in _workers) {
      if (worker.idle) return worker;
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
          worker.urlsToCheck.remove(result.checked.url);
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
    // TODO: periodically check workers and kill them after long inactivity. Mark their current urls as inaccesible.
  }

  /// Sends host globs (e.g. http://example.com/**) to all the workers.
  void _addHostGlobs() {
    for (var worker in _workers) {
      worker.sink.add({verbKey: addHostGlobVerb, dataKey: _hostGlobs.toList()});
    }
  }
}