library linkcheck.link;

import 'package:linkcheck/src/destination.dart';
import 'package:linkcheck/src/origin.dart';

class Link {
  Origin origin;
  Destination destination;
  String fragment;

  Link(this.origin, this.destination, String fragment)
      : fragment = fragment == null || fragment.isEmpty ? null : fragment;

  Link.fromMap(Map<String, Object> map)
      : this(
            new Origin.fromMap(map["origin"] as Map<String, Object>),
            new Destination.fromMap(map["destination"] as Map<String, Object>),
            map["destinationAnchor"]);

  bool get hasError => destination.isBroken;

  bool get hasWarning => breaksAnchor;

  bool get hasInfo => destination.wasDeniedByRobotsTxt;

  bool get breaksAnchor =>
      destination.wasParsed && !destination.satisfiesFragment(fragment);

  Map<String, Object> toMap() => {
        "origin": origin.toMap(),
        "destination": destination.toMap(),
        "destinationAnchor": fragment
      };

  String toString() => "$origin => $destination"
      "${fragment == null ? '' : '#' + fragment} "
      "(${destination.statusDescription})";
}
