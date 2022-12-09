import 'destination.dart';
import 'origin.dart';

class Link {
  final Origin origin;
  Destination destination;
  final String? fragment;

  /// Whether or not this link was marked as skipped.
  ///
  /// User has an option to skip URLs via regexp patterns. When this destination
  /// has a match, [wasSkipped] will be `true`.
  bool wasSkipped = false;

  Link(this.origin, this.destination, String? fragment,
      [this.wasSkipped = false])
      : fragment = fragment == null || fragment.isEmpty ? null : fragment;

  bool get breaksAnchor =>
      !wasSkipped &&
      destination.wasParsed &&
      !destination.satisfiesFragment(fragment);

  /// Returns the destination URL with [fragment] (if there was any).
  ///
  /// For example, let's say the original HTML at `http://example.com/path/`
  /// includes this code:
  ///
  ///     <a href="../about/#contact">...</a>
  ///
  /// In this case [destination]'s [Destination.url] will be
  /// `http://example/about/` (because destinations shouldn't be duplicated
  /// when there are more anchors on the page).
  ///
  /// That works for most needs of linkcheck but sometimes we need
  /// the resolved destination URL _with_ the original fragment. For that,
  /// there is [destinationUrlWithFragment].
  String get destinationUrlWithFragment {
    if (fragment == null) return destination.url;
    return "${destination.url}#$fragment";
  }

  bool get hasError => destination.isBroken; // TODO: add wasSkipped?

  bool get hasInfo => destination.wasDeniedByRobotsTxt;

  bool hasWarning(bool shouldCheckAnchors) =>
      (shouldCheckAnchors && breaksAnchor) || destination.hasNoMimeType;

  @override
  String toString() => "$origin => $destination"
      "${fragment == null ? '' : '#$fragment'} "
      "(${destination.statusDescription})";
}
