import 'package:test/test.dart';

import 'package:linkcheck/src/parsers/url_skipper.dart';

void main() {
  var dummyPath = "dummy_file.txt";

  test("empty file", () {
    var contents = [""];
    var skipper = new UrlSkipper(dummyPath, contents);
    expect(skipper.skips("http://google.com"), false);
    expect(skipper.skips("http://google.com/something/"), false);
    expect(skipper.skips("http://google.com/something/else"), false);
  });

  test("simple pattern", () {
    var contents = ["something"];
    var skipper = new UrlSkipper(dummyPath, contents);
    expect(skipper.skips("http://google.com"), false);
    expect(skipper.skips("http://google.com/something/"), true);
    expect(skipper.skips("http://google.com/something/else"), true);
  });

  test("full regexp (th.*ng)", () {
    var contents = [r"th.*ng"];
    var skipper = new UrlSkipper(dummyPath, contents);
    expect(skipper.skips("http://google.com"), false);
    expect(skipper.skips("http://google.com/something/"), true);
    expect(skipper.skips("http://google.com/something/else"), true);
  });

  test(r"full regexp (\w$)", () {
    var contents = [r"\w$"];
    var skipper = new UrlSkipper(dummyPath, contents);
    expect(skipper.skips("http://google.com"), true);
    expect(skipper.skips("http://google.com/something/"), false);
    expect(skipper.skips("http://google.com/something/else"), true);
  });

  test("multiple patterns on two lines", () {
    var contents = r"""
    \.com$
    /else
    """.trim().split("\n");
    var skipper = new UrlSkipper(dummyPath, contents);
    expect(skipper.skips("http://google.com"), true);
    expect(skipper.skips("http://google.com/something/"), false);
    expect(skipper.skips("http://google.com/something/else"), true);
  });

  test("comments (#) are ignored", () {
    var contents = r"""
    # This is a comment
    \.com$
    /else
    """.trim().split("\n");
    var skipper = new UrlSkipper(dummyPath, contents);
    expect(skipper.skips("http://google.com"), true);
    expect(skipper.skips("http://google.com/something/"), false);
    expect(skipper.skips("http://google.com/something/else"), true);
  });

  test(r"comment escaping (\#) works", () {
    var contents = r"""
    \#
    \.com$
    /else
    """.trim().split("\n");
    var skipper = new UrlSkipper(dummyPath, contents);
    expect(skipper.skips("http://google.com"), true);
    expect(skipper.skips("http://google.com/something/"), false);
    expect(skipper.skips("http://google.com/something/else"), true);
    expect(skipper.skips("http://google.com/#about"), true);
  });

  test("blank lines are ignored", () {
    var contents = r"""
    # This is a comment

    \.com$
    /else
    """.trim().split("\n");
    var skipper = new UrlSkipper(dummyPath, contents);
    expect(skipper.skips("http://google.com"), true);
    expect(skipper.skips("http://google.com/something/"), false);
    expect(skipper.skips("http://google.com/something/else"), true);
  });

  test("hash (#) at end of regexp works", () {
    var contents = ["/path/to/page#"];
    var skipper = new UrlSkipper(dummyPath, contents);
    expect(skipper.skips("http://example.com/path/to/page"), false);
    expect(skipper.skips("http://example.com/path/to/page#rxjs"), true);
  });
}
