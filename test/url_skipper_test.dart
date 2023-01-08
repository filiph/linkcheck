import 'package:test/test.dart';

import 'package:linkcheck/src/parsers/url_skipper.dart';

void main() {
  final dummyPath = 'dummy_file.txt';

  test('empty file', () {
    final contents = [''];
    final skipper = UrlSkipper(dummyPath, contents);
    expect(skipper.skips('http://google.com'), false);
    expect(skipper.skips('http://google.com/something/'), false);
    expect(skipper.skips('http://google.com/something/else'), false);
  });

  test('simple pattern', () {
    final contents = ['something'];
    final skipper = UrlSkipper(dummyPath, contents);
    expect(skipper.skips('http://google.com'), false);
    expect(skipper.skips('http://google.com/something/'), true);
    expect(skipper.skips('http://google.com/something/else'), true);
  });

  test('full regexp (th.*ng)', () {
    final contents = [r'th.*ng'];
    final skipper = UrlSkipper(dummyPath, contents);
    expect(skipper.skips('http://google.com'), false);
    expect(skipper.skips('http://google.com/something/'), true);
    expect(skipper.skips('http://google.com/something/else'), true);
  });

  test(r'full regexp (\w$)', () {
    final contents = [r'\w$'];
    final skipper = UrlSkipper(dummyPath, contents);
    expect(skipper.skips('http://google.com'), true);
    expect(skipper.skips('http://google.com/something/'), false);
    expect(skipper.skips('http://google.com/something/else'), true);
  });

  test('multiple patterns on two lines', () {
    final contents = r'''
    \.com$
    /else
    '''
        .trim()
        .split('\n');
    final skipper = UrlSkipper(dummyPath, contents);
    expect(skipper.skips('http://google.com'), true);
    expect(skipper.skips('http://google.com/something/'), false);
    expect(skipper.skips('http://google.com/something/else'), true);
  });

  test('comments (#) are ignored', () {
    final contents = r'''
    # This is a comment
    \.com$
    /else
    '''
        .trim()
        .split('\n');
    final skipper = UrlSkipper(dummyPath, contents);
    expect(skipper.skips('http://google.com'), true);
    expect(skipper.skips('http://google.com/something/'), false);
    expect(skipper.skips('http://google.com/something/else'), true);
  });

  test(r'comment escaping (\#) works', () {
    final contents = r'''
    \#
    \.com$
    /else
    '''
        .trim()
        .split('\n');
    final skipper = UrlSkipper(dummyPath, contents);
    expect(skipper.skips('http://google.com'), true);
    expect(skipper.skips('http://google.com/something/'), false);
    expect(skipper.skips('http://google.com/something/else'), true);
    expect(skipper.skips('http://google.com/#about'), true);
  });

  test('blank lines are ignored', () {
    final contents = r'''
    # This is a comment

    \.com$
    /else
    '''
        .trim()
        .split('\n');
    final skipper = UrlSkipper(dummyPath, contents);
    expect(skipper.skips('http://google.com'), true);
    expect(skipper.skips('http://google.com/something/'), false);
    expect(skipper.skips('http://google.com/something/else'), true);
  });

  test('hash (#) at end of regexp works', () {
    final contents = ['/path/to/page#'];
    final skipper = UrlSkipper(dummyPath, contents);
    expect(skipper.skips('http://example.com/path/to/page'), false);
    expect(skipper.skips('http://example.com/path/to/page#rxjs'), true);
  });
}
