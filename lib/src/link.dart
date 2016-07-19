library linkcheck.link;

import 'package:linkcheck/src/destination.dart';
import 'package:linkcheck/src/origin.dart';

class Link {
  Origin origin;
  Destination destination;

  Link(this.origin, this.destination);

  Link.fromMap(Map<String, Object> map)
      : this(new Origin.fromMap(map["origin"] as Map<String, Object>),
            new Destination.fromMap(map["destination"] as Map<String, Object>));

  Map<String, Object> toMap() =>
      {"origin": origin.toMap(), "destination": destination.toMap()};

  String toString() => "$origin => $destination "
      "(${destination.statusDescription})";
}
