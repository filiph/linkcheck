library linkcheck.link;

import 'package:linkcheck/src/destination.dart';
import 'package:linkcheck/src/origin.dart';

class Link {
  Origin source;
  Destination destination;

  Link(this.source, this.destination);

  String toString() => "$source => $destination "
      "(${destination.statusDescription})";
}
