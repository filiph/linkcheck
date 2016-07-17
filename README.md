# linkcheck

Very fast link-checking.

### Features:

* Fast crawling
* Sane defaults
  * The most frequent use cases should be only a few arguments.
  * You want to crawl a served site, not directories of files
  * Should follow CLI 'standards' (no @input etc.)
* Brief and meaningful output
  * When everything works, all you want to see is 'Perfect' + stats
  * When things are broken, you want to see where exactly is the problem
    and you want to have it sorted in a sane way
* Useful status code
* Finds everything (CSS url() etc.)