ARG CHVER=latest
FROM clickhouse/clickhouse-server:${CHVER}

# Bridge releases are independent of the server. The base image configures
# ClickHouse's signed apt repository; Microsoft's package adds its signed repo.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates curl unixodbc clickhouse-odbc-bridge=25.1.5.31 \
    && . /etc/os-release \
    && curl --fail --location --connect-timeout 10 --max-time 60 \
      "https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb" \
      --output /tmp/packages-microsoft-prod.deb \
    && dpkg -i /tmp/packages-microsoft-prod.deb \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18=18.6.2.1-1 \
    && rm -f /tmp/packages-microsoft-prod.deb \
    && rm -rf /var/lib/apt/lists/*
