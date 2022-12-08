import '../destination.dart';
import '../link.dart';

class FetchResults {
  final DestinationResult checked;
  final List<Link> links;
  FetchResults(this.checked, this.links);

  FetchResults.fromMap(Map<String, Object?> map)
      : this(
            DestinationResult.fromMap(
                map["checked"] as Map<String, Object?>? ?? {}),
            List<Link>.from((map["links"] as List<Map>? ?? const []).map<Link>(
                (serialization) => Link.fromMap(
                    serialization as Map<String, Object?> ?? {}))));

  Map<String, Object> toMap() => {
        "checked": checked.toMap(),
        "links": links.map((link) => link.toMap()).toList(growable: false)
      };
}
