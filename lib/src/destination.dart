library linkcheck.destination;

import 'dart:io' show ContentType, HttpClientResponse, RedirectInfo;

import 'package:linkcheck/src/parsers/html.dart';

/// RegExp for detecting URI scheme, such as `http:`, `mailto:`, etc.
final _scheme = RegExp(r"$(\w[\w\-]*\w):");

/// Takes a trimmed URL and returns [bool] indicating whether
/// we support the URL's scheme or not. When there is no scheme in the URL,
/// the [source]'s scheme's support is returned.
///
/// [source] must be a fully resolved [Uri] with a non-empty [Uri.scheme]
/// component.
bool checkSchemeSupported(String url, Uri source) {
  var match = _scheme.firstMatch(url);
  String scheme;
  if (match == null) {
    // No scheme provided, so the source's scheme is used.
    scheme = source.scheme;
    assert(source.scheme.isNotEmpty);
  } else {
    scheme = match.group(1);
  }
  return Destination.supportedSchemes.contains(scheme);
}

class BasicRedirectInfo {
  String url;
  int statusCode;

  BasicRedirectInfo.from(RedirectInfo info) {
    url = info.location.toString();
    statusCode = info.statusCode;
  }

  BasicRedirectInfo.fromMap(Map<String, Object> map)
      : url = map["url"] as String,
        statusCode = map["statusCode"] as int;

  Map<String, Object> toMap() => {"url": url, "statusCode": statusCode};
}

class Destination {
  static const List<String> supportedSchemes = ["http", "https", "file"];

  /// This is the naked URL (no fragment).
  final String url;

  /// The uri as specified by source file, without the fragment.
  Uri _uri;

  /// The HTTP status code returned.
  int statusCode;

  /// MimeType of the response.
  ContentType contentType;

  List<BasicRedirectInfo> redirects;

  /// Url after all redirects.
  String finalUrl;

  bool isExternal;

  /// True if this [Destination] is parseable and could contain links to
  /// other destinations. For example, HTML and CSS files are sources. JPEGs
  /// and
  bool isSource = false;

  /// Set of anchors on the page.
  ///
  /// Only for [isSource] == `true`.
  List<String> anchors;

  /// If the URL is unparseable (malformed), this will be `true`.
  bool isInvalid = false;

  /// This is true if this Destination was one of the ones provided at the
  /// start of the crawl.
  bool isSeed = false;

  bool didNotConnect = false;

  // TODO: this field (and some others) will never be updated in Worker
  //   - have them in a separate file so that it's clear why we're not sending
  //     them via toMap?
  bool wasDeniedByRobotsTxt = false;

  int _hashCode;

  Uri _finalUri;

  /// The encoding is not UTF-8 or LATIN-1.
  bool hasUnsupportedEncoding = false;

  // TODO: add #! rewrite
  // https://developers.google.com/webmasters/ajax-crawling/docs/getting-started

  bool wasParsed = false;

  bool _isUnsupportedScheme;

  Destination(Uri uri)
      : url = uri.removeFragment().toString(),
        _uri = uri.removeFragment() {
    _hashCode = url.hashCode;
  }

  factory Destination.fromMap(Map<String, Object> map) {
    var destination = Destination.fromString(map["url"] as String);
    var contentType = map["primaryType"] == null
        ? null
        : ContentType(map["primaryType"] as String, map["subType"] as String);
    destination
      ..statusCode = map["statusCode"] as int
      ..contentType = contentType
      ..redirects = (map["redirects"] as List<Map<String, Object>>)
          ?.map((obj) => BasicRedirectInfo.fromMap(obj))
          ?.toList()
      ..finalUrl = map["finalUrl"] as String
      ..isExternal = map["isExternal"] as bool
      ..isSource = map["isSource"] as bool
      ..anchors = map["anchors"] as List<String>
      ..isInvalid = map["isInvalid"] as bool
      ..didNotConnect = map["didNotConnect"] as bool
      ..wasParsed = map["wasParsed"] as bool
      ..hasUnsupportedEncoding = map["hasUnsupportedEncoding"] as bool;
    return destination;
  }

  Destination.fromString(String url)
      : url = url.contains("#") ? url.split("#").first : url {
    _hashCode = this.url.hashCode;
  }

  Destination.invalid(String url)
      : url = url,
        isInvalid = true {
    _hashCode = url.hashCode;
  }

  Destination.unsupported(String url) : url = url {
    _isUnsupportedScheme = true;
    _hashCode = url.hashCode;
  }

  // TODO: make sure we don't assign the same hashcode to two destinations like
  //       '../' from different subdirectory levels.
  /// Parsed [finalUrl].
  Uri get finalUri => _finalUri ??= Uri.parse(finalUrl ?? url);

  @override
  int get hashCode => _hashCode;

  /// A bad or busted server didn't give us any content type. This is a warning.
  bool get hasNoMimeType => wasTried && contentType == null;

  /// Link that wasn't valid, didn't connect, or the [statusCode] was not
  /// HTTP 200 OK.
  ///
  /// Ignores URIs with unsupported scheme (like `mailto:`).
  bool get isBroken =>
      statusCode != 200 && !wasDeniedByRobotsTxt && !isUnsupportedScheme;

  bool get isCssMimeType =>
      contentType?.primaryType == "text" && contentType?.subType == "css";

  bool get isHtmlMimeType =>
      // Assume the server is just poorly implemented.
      hasNoMimeType ||
      // But if it isn't, then only html destinations are valid.
      contentType?.mimeType == ContentType.html.mimeType;

  bool get isParseableMimeType => isHtmlMimeType || isCssMimeType;

  bool get isPermanentlyRedirected =>
      redirects != null &&
      redirects.isNotEmpty &&
      redirects.first.statusCode == 301;

  bool get isRedirected => redirects != null && redirects.isNotEmpty;

  /// True if the destination URI isn't one of the [supportedSchemes].
  bool get isUnsupportedScheme {
    if (_isUnsupportedScheme != null) return _isUnsupportedScheme;
    bool result = true;
    try {
      // This can throw a FormatException when the URI cannot be parsed.
      result = !supportedSchemes.contains(finalUri.scheme);
    } on FormatException {
      // Pass.
    }
    _isUnsupportedScheme = result;
    return result;
  }

  String get statusDescription {
    if (isUnsupportedScheme) return "scheme unsupported";
    if (isInvalid) return "invalid URL";
    if (didNotConnect) return "connection failed";
    if (wasDeniedByRobotsTxt) return "denied by robots.txt";
    if (hasNoMimeType) return "server reported no mime type";
    if (!wasTried) return "wasn't tried";
    if (statusCode == 200) return "HTTP 200";
    if (isRedirected) {
      var path = redirects.map((redirect) => redirect.statusCode).join(" -> ");
      return "HTTP $path => $statusCode";
    }
    return "HTTP $statusCode";
  }

  Uri get uri {
    if (_uri != null) return _uri;
    try {
      _uri = Uri.parse(url);
    } on FormatException catch (e, s) {
      print("Stack trace: $s");
      throw StateError("Tried parsing '$url' as URI:\n"
          "$e");
    }
    return _uri;
  }

  bool get wasTried => didNotConnect || statusCode != null;

  @override
  bool operator ==(Object other) =>
      other is Destination && other.hashCode == hashCode;

  /// Returns `true` if the [fragment] (such as #something) will find it's mark
  /// on this [Destination]. If the fragment is `null` or empty, it will
  /// automatically succeed.
  bool satisfiesFragment(String fragment) {
    if (fragment == null || fragment == '') return true;
    if (anchors == null) return false;
    return anchors.contains(normalizeAnchor(fragment));
  }

  Map<String, Object> toMap() => {
        "url": url,
        "statusCode": statusCode,
        "primaryType": contentType?.primaryType,
        "subType": contentType?.subType,
        "redirects": redirects?.map((info) => info.toMap())?.toList(),
        "finalUrl": finalUrl,
        "isExternal": isExternal,
        "isSource": isSource,
        "anchors": anchors,
        "isInvalid": isInvalid,
        "didNotConnect": didNotConnect,
        "wasParsed": wasParsed,
        "hasUnsupportedEncoding": hasUnsupportedEncoding
      };

  @override
  String toString() => url;

  void updateFromResult(DestinationResult result) {
    assert(url == result.url);
    finalUrl = result.finalUrl;
    statusCode = result.statusCode;
    contentType = result.primaryType == null
        ? null
        : ContentType(result.primaryType, result.subType);
    redirects = result.redirects;
    isSource = result.isSource;
    anchors = result.anchors;
    didNotConnect = result.didNotConnect;
    wasParsed = result.wasParsed;
    hasUnsupportedEncoding = result.hasUnsupportedEncoding;
  }
}

/// Data about destination coming from a fetch.
class DestinationResult {
  String url;
  String finalUrl;
  int statusCode;
  String primaryType;
  String subType;
  List<BasicRedirectInfo> redirects;
  bool isSource = false;
  List<String> anchors;
  bool didNotConnect = false;
  bool wasParsed = false;
  bool hasUnsupportedEncoding = false;

  DestinationResult.fromDestination(Destination destination)
      : url = destination.url,
        isSource = destination.isSource,
        redirects = [];

  DestinationResult.fromMap(Map<String, Object> map)
      : url = map["url"] as String,
        finalUrl = map["finalUrl"] as String,
        statusCode = map["statusCode"] as int,
        primaryType = map["primaryType"] as String,
        subType = map["subType"] as String,
        redirects = (map["redirects"] as List<Map<String, Object>>)
            .map((obj) => BasicRedirectInfo.fromMap(obj))
            .toList(),
        isSource = map["isSource"] as bool,
        anchors = map["anchors"] as List<String>,
        didNotConnect = map["didNotConnect"] as bool,
        wasParsed = map["wasParsed"] as bool,
        hasUnsupportedEncoding = map["hasUnsupportedEncoding"] as bool;

  Map<String, Object> toMap() => {
        "url": url,
        "finalUrl": finalUrl,
        "statusCode": statusCode,
        "primaryType": primaryType,
        "subType": subType,
        "redirects": redirects.map((info) => info.toMap()).toList(),
        "isSource": isSource,
        "anchors": anchors,
        "didNotConnect": didNotConnect,
        "wasParsed": wasParsed,
        "hasUnsupportedEncoding": hasUnsupportedEncoding
      };

  void updateFromResponse(HttpClientResponse response) {
    statusCode = response.statusCode;
    redirects =
        response.redirects.map((info) => BasicRedirectInfo.from(info)).toList();
    if (redirects.isEmpty) {
      finalUrl = url;
    } else {
      finalUrl = redirects
          .fold(
              Uri.parse(url),
              (Uri current, BasicRedirectInfo redirect) =>
                  current.resolve(redirect.url))
          .toString();
    }
    if (response.headers.contentType != null) {
      primaryType = response.headers.contentType.primaryType;
      subType = response.headers.contentType.subType;
    }
  }
}
