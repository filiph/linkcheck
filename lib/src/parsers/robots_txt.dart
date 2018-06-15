library linkcheck.parsers.robots_txt;

class RobotsBouncer {
  /// The shortest possible identifying part of the user agent.
  ///
  /// So, for example for Googlebot it would be "Googlebot", although
  /// the user agent string is usually longer.
  final String robotName;
  final List<_Rule> _rules = new List<_Rule>();

  RobotsBouncer(Iterable<String> lines, {String forRobot: _asterisk})
      : robotName = forRobot {
    const userAgentString = "User-agent:";
    const disallowString = "Disallow:";

    assert(robotName != null);

    Set<String> currentUserAgents = new Set();
    Set<String> currentPaths = new Set();
    for (var line in lines) {
      line = line.trim();
      if (line.startsWith('#')) continue;
      if (line.isEmpty) {
        if (currentUserAgents.isEmpty || currentPaths.isEmpty) {
          // Invalid rule, discard.
          currentUserAgents = new Set();
          currentPaths = new Set();
          continue;
        }
        _rules.add(new _Rule(currentUserAgents, currentPaths));
        currentUserAgents = new Set();
        currentPaths = new Set();
        continue;
      }
      if (line.startsWith(userAgentString)) {
        line = line.substring(userAgentString.length);
        currentUserAgents.add(line.trim());
        continue;
      }
      if (line.startsWith(disallowString)) {
        line = line.substring(disallowString.length);
        currentPaths.add(line.trim());
        continue;
      }
    }

    // Last rule, if any
    if (currentUserAgents.isNotEmpty && currentPaths.isNotEmpty) {
      _rules.add(new _Rule(currentUserAgents, currentPaths));
    }
  }

  bool allows(String path) {
    if (_rules.any((rule) => rule.fitsRobotName(robotName) && rule.allowsAll)) {
      return true;
    }

    for (var rule in _rules) {
      if (rule.fitsRobotName(robotName) && rule.appliesToPath(path)) {
        return false;
      }
    }
    return true;
  }
}

class _Rule {
  final Set<String> userAgents;
  final Set<String> paths;
  _Rule(this.userAgents, this.paths);

  // 'Disallow:' (with empty rulepath) means something like 'allow all'
  // for fitting bots.
  bool get allowsAll => paths.any((rulePath) => rulePath.isEmpty);

  bool fitsRobotName(String robotName) {
    if (userAgents.contains(_asterisk)) return true;
    robotName = robotName.trim().toLowerCase();
    return userAgents
        .map((userAgent) => userAgent.toLowerCase())
        .any((userAgent) => userAgent.contains(robotName));
  }

  bool appliesToPath(String path) {
    if (allowsAll) return false;
    return paths.any((rulePath) => path.startsWith(rulePath));
  }
}

const _asterisk = "*";
