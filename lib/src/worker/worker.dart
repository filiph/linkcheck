library linkcheck.check.worker;

import 'dart:async';
import 'dart:io' hide Link;
import 'dart:isolate';

import 'package:stream_channel/stream_channel.dart';

import '../destination.dart';
import '../link.dart';

const verbKey = "message";
const dieVerb = "DIE";
const dieMessage = const {verbKey: dieVerb};
const checkVerb = "CHECK";
const checkDoneVerb = "CHECK_DONE";
const unrecognizedVerb = "UNRECOGNIZED";
const unrecognizedMessage = const {verbKey: unrecognizedVerb};
const dataKey = "data";

class Pool {
  /// The number of threads.
  final int count;

  List<Worker> _workers;

  /// The worker which will get the next job.
  int current = 0;

  StreamController<Destination> _checkedDestinations =
      new StreamController<Destination>();
  Stream<Destination> checkedDestinations;

  StreamController<Destination> _newDestinations =
      new StreamController<Destination>();
  Stream<Destination> newDestinations;

  Pool(this.count) {
    checkedDestinations = _checkedDestinations.stream;
    newDestinations = _newDestinations.stream;
  }

  Future<Null> spawn() async {
    _workers = new List<Worker>.generate(count, (_) => new Worker());
    await Future.wait(_workers.map((worker) => worker.spawn()));
    _workers.forEach((worker) => worker.stream.listen((Map message) {
      switch (message[verbKey]) {
        case checkDoneVerb:
          Destination destination = message[dataKey];
          _checkedDestinations.add(destination);
          worker.destinationsToCheck.remove(destination);
          return;
        default:
          throw new StateError("Unrecognized verb from Worker: "
              "${message[verbKey]}");
      }
    }));
  }

  bool get allIdle => _workers.every((worker) => worker.idle);
  bool get allWorking => _workers.every((worker) => !worker.idle);

  /// Finds the worker with the least amount of jobs.
  Worker _pickWorker() {
    int minimumJobs = 1e15.toInt();
    Worker best;
    for (var worker in _workers) {
      if (worker.destinationsToCheck.length < minimumJobs) {
        minimumJobs = worker.destinationsToCheck.length;
        best = worker;
      }
    }
    assert(best != null);
    return best;
  }

  void check(Destination destination) {
    var worker = _pickWorker();
    worker.sink.add({verbKey: checkVerb, dataKey: destination});
    worker.destinationsToCheck.add(destination);
    current = (current + 1) % count;
  }

  Future<Null> close() async {
    await Future.wait(_workers.map((worker) async {
      worker.sink.add(dieMessage);
      await worker.sink.close();
    }));
  }
}

class Worker {
  StreamChannel<Map> _channel;
  StreamSink<Map> _sink;
  StreamSink<Map> get sink => _sink;
  Stream<Map> _stream;
  Stream<Map> get stream => _stream;

  /// TODO: use to find out which destinations to re-check when a worker crashes
  final Set<Destination> destinationsToCheck = new Set<Destination>();

  bool get idle => destinationsToCheck.isEmpty;

  Future<Null> spawn() async {
    assert(_channel == null);
    _channel = await _spawnWorker();
    _sink = _channel.sink;
    _stream = _channel.stream;
  }
}

/// Spawns a worker isolate and returns a [StreamChannel] for communicating with
/// it.
Future<StreamChannel<Map>> _spawnWorker() async {
  var port = new ReceivePort();
  var isolate = await Isolate.spawn(worker, port.sendPort);
  return new IsolateChannel<Map>.connectReceive(port);
}

/// The entrypoint for the worker isolate.
void worker(SendPort port) {
  var channel = new IsolateChannel<Map>.connectSend(port);
  var sink = channel.sink;
  var stream = channel.stream;
  var client = new HttpClient();

  stream.listen((Map message) {
    switch (message[verbKey]) {
      case dieVerb:
        client.close(force: true);
        sink.close();
        return;
      case checkVerb:
        Destination destination = message[dataKey];
        fetch(destination, client).then((results) {
          sink.add({verbKey: checkDoneVerb, dataKey: results.destination});
          // TODO: send new links
        });
        return;
      default:
        sink.add(unrecognizedMessage);
    }
  });
}

class FetchResults {
  Destination destination;
  List<Link> links;
}

Future<FetchResults> fetch(Destination destination, HttpClient client) async {

}