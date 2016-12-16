# linkcheck

[![Build Status](https://travis-ci.org/filiph/linkcheck.svg?branch=master)](https://travis-ci.org/filiph/linkcheck)

Very fast link-checking.

![linkcheck versus the popular blc tool](https://raw.githubusercontent.com/filiph/linkcheck/master/assets/img/linkcheck-vs-blc.gif)

## Philosophy:

A good utility is custom-made for a job. There are many link checkers out there,
but none of them seems to be striving for the following set of goals.

### Crawls fast

* You want to run the link-checker _at least_ before every deploy (on CI 
  or manually). When it takes ages, you're less likely to do so.
  
* `linkcheck` is currently several times faster than 
  [blc](https://www.npmjs.com/package/broken-link-checker) and all other link
  checkers that go to at least comparable depth. It is 40 times faster than the
  only tool that goes to the same depth 
  ([linkchecker](https://github.com/wummel/linkchecker)).

### Finds all relevant problems

* No link-checker can _guarantee_ correct results: the web is too flaky 
  for that. But at least the tool should correctly parse the HTML (not just
  try to guess what's a URL and what isn't) and 
  the CSS (for `url(...)` links).
  
  * PENDING: srcset support
  
* `linkcheck` finds more than [linklint](http://www.linklint.org/) and 
  [blc](https://www.npmjs.com/package/broken-link-checker). It finds the
  same amount or more problems than the best alternative, 
  [linkchecker](https://github.com/wummel/linkchecker).

#### Leaves out irrelevant problems

* `linkcheck` doesn't attempt to render JavaScript. It would make
  it at least an order of magnitude slower and way more complex. (For example,
  what links and buttons should the tool attempt to click, and how many
  times? Should we only click visible links? How exactly do we detect broken
  links?) Validating SPAs is a very different problem than checking static 
  links, and should be approached by dedicated tools.
  
* `linkcheck` only supports `http:` and `https:`. It won't try to check
  FTP or telnet or nntp links.
  
* `linkcheck` doesn't validate file system directories. Servers often behave
  very differently than file systems, so validating links on the file system
  often leads to both false positives and false negatives. Links should be 
  checked in their natural habitat, and as close to the production environment
  as possible. You can (and should) run `linkcheck` on your localhost server,
  of course.
    
### Good <abbr title="User Experience">UX</abbr>

* Yes, a command line utility can have good or bad UX. It has mostly to do with
  giving sane defaults, not forcing users to learn new constructs, not making
  them type more than needed, and showing concise output.

* The most frequent use cases should be only a few arguments. 

  * For example, unleashing `linkcheck` on http://localhost:4001/ can be done 
    via `linkcheck :4001`.
  
* `linkcheck` doesn't throttle itself on localhost.

* `linkcheck` follows POSIX CLI standards (no `@input` and similar constructs
  like in [linklint](http://www.linklint.org/)).

#### Brief and meaningful output

* When everything works, you don't want to see a huge list of links. 

  * In this scenario, `linkcheck` just outputs 'Perfect' and some stats on
    a single line.
    
* When things are broken, you want to see where exactly is the problem
  and you want to have it sorted in a sane way.
  
  * `linkcheck` lists broken links by their source URL first so that you can
    fix many links at once. It also sorts the URLs alphabetically, and shows
    both the exact location of the link (line:column) and the anchor
    text (or the tag if it wasn't an anchor).
  
* For <abbr title="Continuous Integration">CI</abbr> builds, you want non-zero 
  exit code whenever there is a problem.
  
  * `linkcheck` returns status code `1` if there are warnings, and
    status code `2` if there are errors.

It goes without saying that `linkcheck` honors robots.txt and throttles itself
when accessing websites.

## Installation

#### Step 1. Install Dart

Full installation guides per platform:

* [Install Dart on Windows](https://www.dartlang.org/install/windows)
* [Install Dart on Linux](https://www.dartlang.org/install/linux)
* [Install Dart on Mac](https://www.dartlang.org/install/mac)

**For example,** on a Mac, assuming you have [homebrew](http://brew.sh/), 
you just run:

```
$ brew tap dart-lang/dart
$ brew install dart
```

#### Step 2. Install `linkcheck`

Once Dart is installed, run:

```
$ pub global activate linkcheck
```

Pub installs executables into `~/.pub-cache/bin`, which may not be on your path.
You can fix that by adding the following to your shell's config file (.bashrc, 
.bash_profile, etc.):

```
export PATH="$PATH":"~/.pub-cache/bin"
```

Then either restart the terminal or run `source ~/.bash_profile` (assuming
`~/.bash_profile` is where you put the PATH export above).

## Usage

If in doubt, run `linkcheck -h`. Here are some examples to get you started.

#### Localhost

Running `linkcheck` without arguments will try to crawl 
http://localhost:8080/ (which is the most common local server URL).

* `linkcheck` to crawl the site and ignore external links
* `linkcheck -e` to try external links

If you run your local server on http://localhost:4000/, for example, you can do:

* `linkcheck :4000` to crawl the site and ignore external links
* `linkcheck :4000 -e` to try external links

`linkcheck` will _not_ throttle itself when accessing localhost. It will go as
fast as possible.


#### Deployed sites

* `linkcheck www.example.com` to crawl www.example.com and ignore external links
* `linkcheck https://www.example.com` to start directly on https
* `linkcheck www.example.com www.other.com` to crawl both sites and check links
  between the two (but ignore external links outside those two sites)

#### Many entry points

Assuming you have a text file `mysites.txt` like this:

```
http://egamebook.com/
http://filiph.net/
https://alojz.cz/
```

You can run `linkcheck -i mysites.txt` and it will crawl all of them and also
check links between them. This is useful for:

1. Link-checking projects spanning many domains (or subdomains).
2. Checking all your public websites / blogs / etc.

There's another use for this, and that is when you have a list of inbound links,
like this:

```
http://www.dartlang.org/
http://www.dartlang.org/tools/
http://www.dartlang.org/downloads/
```

You probably want to make sure you never break your inbound links. For example,
if a page changes URL, the previous URL should still work (redirecting to the
new page when appropriate).

Where do you get a list of inbound links? Try your site's sitemap.xml as
a starting point, and — additionally — try something like the Google Webmaster 
Tools’ [crawl error page](https://www.google.com/webmasters/tools/crawl-errors).

#### Skipping URLs

Sometimes, it is legitimate to ignore some failing URLs. This is done via
the `--skip-file` option.

Let's say you're working on a site and a significant portion of it is currently
under construction. You can create a file called `my_skip_file.txt` and
fill it with regular expressions like so:

```
# Lines starting with a hash are ignored.
admin/
\.s?css$
\#info
```

The file above includes a comment on line 1. Line 2 contains a broad
regular expression that will make linkcheck ignore any link to a URL containing
`admin/` anywhere in it. Line 3 shows that there is full support for regular
expressions – it will ignore URLs ending with `.css` and `.scss`. Line 4
shows the only special escape sequence. If you need to start your regular
expression with a `#` (which linkcheck would normally parse as a comment) you
can precede the `#` with a backslash (`\`)

To use this file, you run linkcheck like this:

```
linkcheck example.com --skip-file my_skip_file.txt
```

Regular expressions are hard. If you want to debug, use the `-d` option to make
sure linkcheck is ignoring exactly what you want. 