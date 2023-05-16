# WIP scraper to crawl the docs and populate ClickHouse

Uses Scrapy.  https://docs.scrapy.org/en/latest/intro/tutorial.html

The Algolia crawler docker image uses Scrapy also.  That image is no longer supported, so
I started from scratch.  There is probably some good info in their 
[crawler configuration](https://github.com/algolia/docsearch-scraper/tree/master/scraper/src)
and I will probably look at that.

## Docker

Docker is used to run this, a very simple Dockerfile installs Scrapy and its dependencies, and then copies in the Scrapy config from the `mycrawler` dir.  

## Build

```bash
docker build --network=host -t crawler .
```

## Run
```bash
docker run  -ti \
  --name    crawl \
  --network host \
  crawler
```

