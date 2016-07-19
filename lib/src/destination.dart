library linkcheck.destination;

import 'dart:io' show ContentType, HttpClientResponse, RedirectInfo;

class Destination {
  static const List<String> supportedSchemes = const ["http", "https", "file"];

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

  Destination(Uri uri)
      : uri = uri,
        uriWithoutFragment = uri.removeFragment(),
        _hashCode = uri.hashCode;

  factory Destination.fromMap(Map<String, Object> map) {
    var uri = Uri.parse(map["uri"]);
    var destination = new Destination(uri);
    var contentType = map["primaryType"] == null
        ? null
        : new ContentType(map["primaryType"], map["subType"]);
    destination
      ..statusCode = map["statusCode"]
      ..contentType = contentType
      ..redirects = [] // TODO
      ..finalUri = Uri.parse(map["finalUri"])
      ..isExternal = map["isExternal"]
      ..isSource = map["isSource"]
      ..hashAnchors = new Set.from(map["hashAnchors"])
      ..isInvalid = map["isInvalid"]
      ..didNotConnect = map["didNotConnect"]
      ..isUnsupportedScheme = map["isUnsupportedScheme"];
    return destination;
  }

  final int _hashCode;
  int get hashCode => _hashCode;

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
  bool operator ==(other) => other is Destination && other.hashCode == hashCode;

  Map<String, Object> toMap() => {
        "uri": uri.toString(),
        "statusCode": statusCode,
        "primaryType": contentType?.primaryType,
        "subType": contentType?.subType,
        "redirects": [], // TODO
        "finalUri": finalUri.toString(),
        "isExternal": isExternal,
        "isSource": isSource,
        "hashAnchors": hashAnchors.toList(growable: false),
        "isInvalid": isInvalid,
        "didNotConnect": didNotConnect,
        "isUnsupportedScheme": isUnsupportedScheme
      };

  String toString() => uri.toString();

  void updateFrom(Destination other) {
    isSource = other.isSource;
    statusCode = other.statusCode;
    didNotConnect = other.didNotConnect;
    isUnsupportedScheme = other.isUnsupportedScheme;
    redirects = other.redirects;
    isExternal = other.isExternal;
    isInvalid = other.isInvalid;
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
