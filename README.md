# linkcheck

Very fast link-checking.

## Philosophy:

* Fast crawling is key
  * You want to run the link-checker _at least_ before every deploy (on CI 
    or manually). When it takes ages, you're less likely to do so.
  * linkcheck is currently several times faster than blc
* Finds everything important
  * No link-checker can guarantee correct results: the web is too flaky 
    for that.
  * But at least the tool should correctly parse the HTML (not just try to
    guess what's a URL and what isn't) _and_ the CSS (for `url(...)` links).
  * The tool already finds more than `linklint` and `blc`, and it has fewer
    false positives.
* Sane defaults (easy things are easy, advanced things are possible)
  * The most frequent use cases should be only a few arguments. For example,
    unleashing `linkcheck` on http://localhost:4001 can be done via 
    `linkcheck :4001`. 
  * You want to crawl a served site, not directories of files.
  * Ignores throttling and robots.txt on localhost.
  * Should follow CLI 'standards' (no `@input` etc.)
* Brief and meaningful output
  * When everything works, all you want to see is 'Perfect' + stats.
  * When things are broken, you want to see where exactly is the problem
    and you want to have it sorted in a sane way.
  * linkcheck does this.
* Useful status code
  * For CI build, `linkcheck` returns status code `1` if there are warnings, and
    status code `2` if there are errors.


## Installation

#### Step 1. Install Dart

[Full installation guide here](https://www.dartlang.org/install). For example, on a Mac, assuming you have [homebrew](http://brew.sh/), run:

```
$ brew tap dart-lang/dart
$ brew install dart
```

#### Step 2. Install `linkcheck`

```
pub global activate linkcheck
```

Pub installs executables into `~/.pub-cache/bin`, which may not be on your path.
You can fix that by adding the following to your shell's config file (.bashrc, 
.bash_profile, etc.):

```
export PATH="$PATH":"~/.pub-cache/bin"
```

Then either restart the terminal or run `source ~/.bash_profile` (assuming
`~/.bash_profile` is where you put the PATH export above).

That's it.

## Usage

If in doubt, run `linkcheck -h`. Here are some examples to get you started.

#### Localhost

Assuming you run your server on http://localhost:8000/, you can do:

* `linkcheck :8000` to crawl the site and ignore external links
* `linkcheck :8000 -e` to try external links

#### Deployed sites

* `linkcheck www.example.com` to crawl www.example.com and ignore external links
* `linkcheck https://www.example.com` to start directly on https
* `linkcheck www.example.com www.other.com` to crawl both sites and check links
  between the two (but ignore external links outside those two sites)

Assuming you have a text file `mysites.txt` like this:

```
http://egamebook.com/
http://filiph.net/
https://alojz.cz/
```

You can run `linkcheck -i mysites.txt` and it will crawl all of them and also
check links between them.