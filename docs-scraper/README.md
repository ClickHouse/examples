# WIP scraper to crawl the docs and populate ClickHouse

Uses Scrapy.  https://docs.scrapy.org/en/latest/intro/tutorial.html

The Algolia crawler docker image uses Scrapy also.  That image is no longer supported, so
I started from scratch.  There is probably some good info in their 
[crawler configuration](https://github.com/algolia/docsearch-scraper/tree/master/scraper/src)
and I will probably look at that.

## Docker

Docker is used to run this, a very simple Dockerfile installs Scrapy and its dependencies.

## Build

```bash
docker build --network=host -t crawler .
```

## Start the container

The `mycrawler` directory gets mounted into the container, and the container launches a bash shell. 

```bash
docker run  --rm -ti \
  --name    crawl \
  --network host \
  --mount type=bind,source="$(pwd)"/mycrawler,target=/usr/src/app/mycrawler \
crawler
```

## Crawl clickhouse.com/docs

Scrapy gets the list of pages (URLs) from the file at https://clickhouse.com/docs/sitemap.xml and process the list.  This command starts a crawl:

```bash
scrapy crawl clickhouse-docs
```

## Enter an interactive Scrapy shell

```bash
scrapy shell
```

