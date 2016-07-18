library linkcheck.destination;

import 'dart:io' show ContentType, HttpClientResponse, RedirectInfo;

class Destination {
  /// The uri as specified by source file.
  final Uri uri;
  final Uri uriWithoutFragment;

  /// The HTTP status code returned.
  int statusCode;

  /// MimeType of the response.
  ContentType contentType;

  List<RedirectInfo> redirects;

  /// Uri after all redirects.
  Uri finalUri;

  bool isExternal = false;

  /// True if this [Destination] is parseable and could contain links to
  /// other destinations. For example, HTML and CSS files are sources. JPEGs
  /// and
  bool isSource = false;

  /// Only for [isSource] == `true`.
  Set<String> hashAnchors = new Set<String>();

  bool isInvalid = false;
  bool didNotConnect = false;

  /// True if the destination URI isn't one of the [supportedSchemes].
  bool isUnsupportedScheme = false;

  static const List<String> supportedSchemes = const ["http", "https", "file"];

  Destination(Uri uri)
      : uri = uri,
        uriWithoutFragment = uri.removeFragment();

  int get hashCode => uri.hashCode;

  /// Link that wasn't valid, didn't connect, or the [statusCode] was not
  /// HTTP 200 OK.
  ///
  /// Ignores URIs with unsupported scheme (like `mailto:`).
  bool get isBroken => statusCode != 200;

  bool get isHtmlMimeType => contentType.mimeType == ContentType.HTML.mimeType;

  bool get isPermanentlyRedirected =>
      redirects != null &&
      redirects.isNotEmpty &&
      redirects.first.statusCode == 301;

  bool get isRedirected => redirects != null && redirects.isNotEmpty;

  String get statusDescription {
    if (isInvalid) return "invalid URL";
    if (didNotConnect) return "connection failed";
    if (isUnsupportedScheme) return "scheme unsupported";
    if (!wasTried) return "wasn't tried";
    if (statusCode == 200) return "HTTP 200";
    if (isRedirected) {
      var path = redirects.map((redirect) => redirect.statusCode).join(" -> ");
      return "HTTP $path => $statusCode";
    }
    return "HTTP $statusCode";
  }

  bool get wasTried => didNotConnect || statusCode != null;

  bool operator ==(other) => other is Destination && other.uri == uri;
  String toString() => uri.toString();

  void updateFrom(Destination other) {
    statusCode = other.statusCode;
    isUnsupportedScheme = other.isUnsupportedScheme;
    redirects = other.redirects;
    isExternal = other.isExternal;
    finalUri =
        other.finalUri?.removeFragment()?.replace(fragment: uri.fragment) ??
            uri;
    contentType = other.contentType;
  }

  void updateFromResponse(HttpClientResponse response) {
    statusCode = response.statusCode;
    redirects = response.redirects;
    finalUri = redirects.isNotEmpty ? redirects.last.location : uri;
    contentType = response.headers.contentType;
  }
}
