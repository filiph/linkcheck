## 2.0.19

- Update to latest dependencies
- Use `pkg:cli_pkg` for creating binaries in CI.
  Thanks
  [Guillaume](https://github.com/filiph/linkcheck/commits?author=Mogztter)!

## 2.0.18

- Allow the latest `pkg:args`

## 2.0.17

- Update to latest dependencies.
- Require Dart 2.12.

## 2.0.16

- Add a summary of the most broken links (as opposed to just warnings) 
  at the end of the listing. This only happens when most of the normal listing
  above is mostly (50%+) warnings. This should help when a big site has
  thousands of small warnings because of, say, missing anchors, but the author
  is currently trying to catch the failing errors.
- Fix `--show-redirects` functionality.
  [Thanks @nfagerlund!](https://github.com/filiph/linkcheck/pull/64)!

## 2.0.15

- Improve stability by handling several failures more gracefully
  ([#57](https://github.com/filiph/linkcheck/issues/57),
  [#63](https://github.com/filiph/linkcheck/issues/63),
  [#51](https://github.com/filiph/linkcheck/issues/51),
  [#40](https://github.com/filiph/linkcheck/issues/40))

## 2.0.14

- Add the `--no-check-anchors` flag, which prevents reporting missing anchors
  as problems. This is useful when the link-checked website uses anchors 
  (like `#play` or `#user=bob`) for dynamic content (i.e. they are handled
  by JavaScript and don't exist in the static HTML).
  [Thanks @emielbeinema](https://github.com/filiph/linkcheck/pull/56)
  for this contribution!

## 2.0.13

- Add the `--show-redirects` flag, which reports redirected links.
  This is handy if you want to minimize the number of hoops the browser needs
  to jump through to get to linked pages. Ideally, all your site's links
  are direct, with zero redirects.
  [Thanks @emielbeinema](https://github.com/filiph/linkcheck/pull/54)
  for this contribution!
- Make everything more type-safe by disallowing Dart features "implicit-casts"
  and "implicit-dynamic".
- Turn on `pedantic` linter.

## 2.0.12

- Don’t assume contentType in HTTP headers is set

## 2.0.11

- Resolve a bug with unicode character counting in HTML.

## 2.0.10

- Guard against servers that do not provide `Content-Type`. No guarantees about
  crawling such servers but at least `linkcheck` will not crash.

## 2.0.9

- Prepare for upcoming change to HttpRequest and HttpClientResponse
- Add Docker skipfile documentation to README

## 2.0.8

- Style fixes to achieve 100% health metric on pub.dev.
- Add programmatic usage in `example/example.dart`.

## 2.0.7

- Upgrade dependencies to latest.
- Walk around `csslib` bug where some CSS makes the parser crash. This will
  currently just ignore the CSS file.

## 2.0.6

- Add support for `--connection-failures-as-warnings` flag.

## 2.0.5

- Fix checking of anchors containing non-ASCII chars.

## 2.0.4

- Set min SDK to 2.0.0.

## 2.0.3

- Add missing dependency on stream_channel.

## 2.0.2

- Fix minor problems with Dart 2 upgrade.

## 2.0.1

- Set max SDK version to <3.0.0.

## 2.0.0, 2.0.0+1

- First Dart-2-only version.

## 1.0.6

- Last version compatible with Dart 1 and Dart 2.
