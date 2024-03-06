FROM clickhouse/clickhouse-server:23.10

# Install the ODBC driver

RUN apt-get update && apt-get install -y --no-install-recommends unixodbc \
    && apt-get install -y freetds-bin freetds-common freetds-dev libct4 libsybdb5 \
    && apt-get install tdsodbc
