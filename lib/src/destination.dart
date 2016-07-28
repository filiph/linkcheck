library linkcheck.destination;

import 'dart:io' show ContentType, HttpClientResponse, RedirectInfo;

class BasicRedirectInfo {
  String url;
  int statusCode;

  BasicRedirectInfo.from(RedirectInfo info) {
    url = info.location.toString();
    statusCode = info.statusCode;
  }

  BasicRedirectInfo.fromMap(Map<String, Object> map)
      : url = map["url"],
        statusCode = map["statusCode"];

  Map<String, Object> toMap() => {"url": url, "statusCode": statusCode};
}

class Destination {
  static const List<String> supportedSchemes = const ["http", "https", "file"];

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

  Destination(Uri uri)
      : url = uri.removeFragment().toString(),
        _uri = uri.removeFragment() {
    _hashCode = url.hashCode;
  }

  factory Destination.fromMap(Map<String, Object> map) {
    var destination = new Destination.fromString(map["url"]);
    var contentType = map["primaryType"] == null
        ? null
        : new ContentType(map["primaryType"], map["subType"]);
    destination
      ..statusCode = map["statusCode"]
      ..contentType = contentType
      ..redirects = (map["redirects"] as List<Map<String, Object>>)
          ?.map((obj) => new BasicRedirectInfo.fromMap(obj))
          ?.toList()
      ..finalUrl = map["finalUrl"]
      ..isExternal = map["isExternal"]
      ..isSource = map["isSource"]
      ..anchors = map["anchors"] as List<String>
      ..isInvalid = map["isInvalid"]
      ..didNotConnect = map["didNotConnect"]
      ..wasParsed = map["wasParsed"]
      ..hasUnsupportedEncoding = map["hasUnsupportedEncoding"];
    return destination;
  }

  Destination.fromString(String url)
      : url = url.contains("#") ? url.split("#").first : url {
    _hashCode = this.url.hashCode;
  }

  Destination.invalid(String url)
      : url = url,
        isInvalid = true;

  /// Parsed [finalUrl].
  Uri get finalUri => _finalUri ??= Uri.parse(finalUrl ?? url);

  int get hashCode => _hashCode;

  /// Link that wasn't valid, didn't connect, or the [statusCode] was not
  /// HTTP 200 OK.
  ///
  /// Ignores URIs with unsupported scheme (like `mailto:`).
  bool get isBroken => statusCode != 200 && !wasDeniedByRobotsTxt;

  bool get isCssMimeType =>
      contentType.primaryType == "text" && contentType.subType == "css";

  bool get isHtmlMimeType => contentType.mimeType == ContentType.HTML.mimeType;

  bool get isParseableMimeType => isHtmlMimeType || isCssMimeType;

  bool get isPermanentlyRedirected =>
      redirects != null &&
      redirects.isNotEmpty &&
      redirects.first.statusCode == 301;

  bool get isRedirected => redirects != null && redirects.isNotEmpty;

  /// True if the destination URI isn't one of the [supportedSchemes].
  bool get isUnsupportedScheme => !supportedSchemes.contains(finalUri.scheme);

  String get statusDescription {
    if (isInvalid) return "invalid URL";
    if (didNotConnect) return "connection failed";
    if (wasDeniedByRobotsTxt) return "denied by robots.txt";
    if (isUnsupportedScheme) return "scheme unsupported";
    if (!wasTried) return "wasn't tried";
    if (statusCode == 200) return "HTTP 200";
    if (isRedirected) {
      var path = redirects.map((redirect) => redirect.statusCode).join(" -> ");
      return "HTTP $path => $statusCode";
    }
    return "HTTP $statusCode";
  }

  Uri get uri => _uri ??= Uri.parse(url);

  bool get wasTried => didNotConnect || statusCode != null;

  bool wasParsed = false;

  bool operator ==(other) => other is Destination && other.hashCode == hashCode;

  /// Returns `true` if the [fragment] (such as #something) will find it's mark
  /// on this [Destination]. If the fragment is `null` or empty, it will
  /// automatically succeed.
  bool satisfiesFragment(String fragment) {
    if (fragment == null || fragment == '') return true;
    if (anchors == null) return false;
    return anchors.contains(fragment);
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

  String toString() => url;

  void updateFromResult(DestinationResult result) {
    assert(url == result.url);
    finalUrl = result.finalUrl;
    statusCode = result.statusCode;
    contentType = result.primaryType == null
        ? null
        : new ContentType(result.primaryType, result.subType);
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
      : url = map["url"],
        finalUrl = map["finalUrl"],
        statusCode = map["statusCode"],
        primaryType = map["primaryType"],
        subType = map["subType"],
        redirects = (map["redirects"] as List<Map<String, Object>>)
            .map((obj) => new BasicRedirectInfo.fromMap(obj))
            .toList(),
        isSource = map["isSource"],
        anchors = map["anchors"] as List<String>,
        didNotConnect = map["didNotConnect"],
        wasParsed = map["wasParsed"],
        hasUnsupportedEncoding = map["hasUnsupportedEncoding"];

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
    redirects = response.redirects
        .map((info) => new BasicRedirectInfo.from(info))
        .toList();
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
    primaryType = response.headers.contentType.primaryType;
    subType = response.headers.contentType.subType;
  }
}
