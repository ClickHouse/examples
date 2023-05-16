FROM python:3
WORKDIR /usr/src/app

# Install Scrapy and prerequisites
COPY requirements.txt requirements.txt
RUN pip3 install --no-cache-dir -r requirements.txt

# Copy in the scrapy project (configuration)
COPY mycrawler mycrawler

# Run the scraper
WORKDIR /usr/src/app/mycrawler
CMD [ "scrapy", "crawl", "example" ]
