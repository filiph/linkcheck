library linkcheck.uri_glob;

import 'package:glob/glob.dart';
import 'package:path/path.dart';

class UriGlob {
  static final _urlContext = new Context(style: Style.url);

  /// Matches the 'authority' portion of the URI, e.g. localhost:4000.
  final String authority;

  /// Matches everything that comes after host.
  final Glob glob;

  UriGlob(String glob)
      : this._(
            Uri.parse(glob).authority,
            new Glob(Uri.parse(glob).path,
                context: _urlContext, caseSensitive: true));
  UriGlob._(this.authority, this.glob);

  bool matches(Uri uri) {
    if (uri.authority != authority) return false;
    var path = uri.path;
    // Fix http://example.com into http://example.com/.
    if (path.isEmpty) path = "/";
    return glob.matches(path);
  }
}
