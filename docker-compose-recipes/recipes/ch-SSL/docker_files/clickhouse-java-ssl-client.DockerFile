FROM eclipse-temurin:7-jdk

# where to host the app
RUN mkdir -p /clickhouse-java-ssl-client/certs

WORKDIR /clickhouse-java-ssl-client


