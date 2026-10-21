FROM clickhouse/clickhouse-server@sha256:05d2e46507afdcf08da46e5528b68847104dbbed691c327e505414b4b7f4e4c8
USER root
RUN apt-get update && apt-get install -y --no-install-recommends python3 strace python3-pip && rm -rf /var/lib/apt/lists/*
RUN python3 -m pip install --no-cache-dir avro==1.12.2 clickhousectl==0.4.2
COPY setup.py pins.py /opt/
ARG CLICKHOUSECTL_RESOLVER_INPUT=26.8
RUN DO_NOT_TRACK=1 CLICKHOUSECTL_RESOLVER_INPUT="$CLICKHOUSECTL_RESOLVER_INPUT" python3 /opt/setup.py
WORKDIR /work
ENTRYPOINT ["/bin/sh", "-c", "sleep infinity"]
