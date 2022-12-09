import '../destination.dart';
import '../link.dart';

class FetchResults {
  final DestinationResult checked;
  final List<Link> links;

  FetchResults(this.checked, this.links);

  @override
  String toString() {
    return 'FetchResults{checked: $checked, links: $links}';
  }
}
