# Use the ClickHouse server image
FROM clickhouse/clickhouse-server:24.3

# Copy your user configuration file and schema file into the container
COPY users.xml /etc/clickhouse-server/users.xml
COPY schemafile.sql /docker-entrypoint-initdb.d/schemafile.sql

# Set ownership for the configuration file
RUN chown clickhouse:clickhouse /etc/clickhouse-server/users.xml

# Expose port 8123
EXPOSE 8123

# Healthcheck to ensure ClickHouse server is ready
HEALTHCHECK --interval=5s --timeout=3s --retries=10 CMD clickhouse-client --query "SELECT 1"

# Start ClickHouse server and run the schema file
CMD ["bash", "-c", "/entrypoint.sh & while ! clickhouse-client --query 'SELECT 1' &>/dev/null; do echo 'Waiting for ClickHouse server to start...'; sleep 1; done; clickhouse-client --user default --password devclickhouse123  --query='source /docker-entrypoint-initdb.d/schemafile.sql'; tail -f /dev/null"]

