import 'package:test/test.dart';

import 'package:linkcheck/src/parsers/robots_txt.dart';

void main() {
  var robotName = "linkcheck";
  test("disallow everything", () {
    List<String> contents = """
      User-agent: *
      Disallow: /
      """
        .split("\n")
        .map((line) => line.trim())
        .toList(growable: false);
    var robots = RobotsBouncer(contents, forRobot: robotName);

    expect(robots.allows("/"), isFalse);
    expect(robots.allows("/#something"), isFalse);
    expect(robots.allows("/?query=something"), isFalse);
    expect(robots.allows("/something"), isFalse);
    expect(robots.allows("/something/other"), isFalse);
  });

  test("allow everything (empty disallow)", () {
    List<String> contents = """
      User-agent: *
      Disallow:
      """
        .split("\n")
        .map((line) => line.trim())
        .toList(growable: false);
    var robots = RobotsBouncer(contents, forRobot: robotName);

    expect(robots.allows("/"), isTrue);
    expect(robots.allows("/#something"), isTrue);
    expect(robots.allows("/?query=something"), isTrue);
    expect(robots.allows("/something"), isTrue);
    expect(robots.allows("/something/other"), isTrue);
  });

  test("allow everything (empty disallow, no last line)", () {
    List<String> contents = """
      User-agent: *
      Disallow:"""
        .split("\n")
        .map((line) => line.trim())
        .toList(growable: false);
    var robots = RobotsBouncer(contents, forRobot: robotName);

    expect(robots.allows("/"), isTrue);
    expect(robots.allows("/#something"), isTrue);
    expect(robots.allows("/?query=something"), isTrue);
    expect(robots.allows("/something"), isTrue);
    expect(robots.allows("/something/other"), isTrue);
  });

  test("allow everything (empty file)", () {
    List<String> contents = """
      """
        .split("\n")
        .map((line) => line.trim())
        .toList(growable: false);
    var robots = RobotsBouncer(contents, forRobot: robotName);

    expect(robots.allows("/"), isTrue);
    expect(robots.allows("/#something"), isTrue);
    expect(robots.allows("/?query=something"), isTrue);
    expect(robots.allows("/something"), isTrue);
    expect(robots.allows("/something/other"), isTrue);
  });

  test("disallow subdirectory", () {
    List<String> contents = """
      User-agent: *
      Disallow: /something/
      """
        .split("\n")
        .map((line) => line.trim())
        .toList(growable: false);
    var robots = RobotsBouncer(contents, forRobot: robotName);

    expect(robots.allows("/"), isTrue);
    expect(robots.allows("/#something"), isTrue);
    expect(robots.allows("/?query=something"), isTrue);
    expect(robots.allows("/something"), isTrue);
    expect(robots.allows("/something/other"), isFalse);
  });

  test("disallow a few different files", () {
    List<String> contents = """
      User-agent: *
      Disallow: /~joe/junk.html
      Disallow: /~joe/foo.html
      Disallow: /~joe/bar.html
      """
        .split("\n")
        .map((line) => line.trim())
        .toList(growable: false);
    var robots = RobotsBouncer(contents, forRobot: robotName);

    expect(robots.allows("/"), isTrue);
    expect(robots.allows("/#something"), isTrue);
    expect(robots.allows("/~joe/junk.html"), isFalse);
    expect(robots.allows("/~joe/foo.html"), isFalse);
    expect(robots.allows("/~joe/bar.html"), isFalse);
    expect(robots.allows("/~joe/bar.html#"), isFalse);
    expect(robots.allows("/~joe/baz.html"), isTrue);
  });

  test("disallow doesn't apply for different bot", () {
    List<String> contents = """
      User-agent: BadBot
      Disallow: /
      """
        .split("\n")
        .map((line) => line.trim())
        .toList(growable: false);
    var robots = RobotsBouncer(contents, forRobot: robotName);

    expect(robots.allows("/"), isTrue);
    expect(robots.allows("/#something"), isTrue);
    expect(robots.allows("/?query=something"), isTrue);
    expect(robots.allows("/something"), isTrue);
    expect(robots.allows("/something/other"), isTrue);
  });

  test("disallow applies for matching bot", () {
    List<String> contents = """
      User-agent: $robotName
      Disallow: /something/
      """
        .split("\n")
        .map((line) => line.trim())
        .toList(growable: false);
    var robots = RobotsBouncer(contents, forRobot: robotName);

    expect(robots.allows("/"), isTrue);
    expect(robots.allows("/#something"), isTrue);
    expect(robots.allows("/?query=something"), isTrue);
    expect(robots.allows("/something"), isTrue);
    expect(robots.allows("/something/other"), isFalse);
  });

  test("allows a single matching bot", () {
    List<String> contents = """
      User-agent: $robotName
      Disallow:

      User-agent: *
      Disallow: /
      """
        .split("\n")
        .map((line) => line.trim())
        .toList(growable: false);
    var robots = RobotsBouncer(contents, forRobot: robotName);

    expect(robots.allows("/"), isTrue);
    expect(robots.allows("/#something"), isTrue);
    expect(robots.allows("/?query=something"), isTrue);
    expect(robots.allows("/something"), isTrue);
    expect(robots.allows("/something/other"), isTrue);
  });
}
