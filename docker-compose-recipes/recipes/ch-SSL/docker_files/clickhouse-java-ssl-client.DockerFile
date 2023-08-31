FROM eclipse-temurin:7-jdk

# where to host the app
RUN mkdir /clickhouse-java-ssl-client

# use to mount the clickhouse rootCA cert as app needs to add it to its keystore
RUN mkdir /clickhouse-java-ssl-client/certs

WORKDIR /clickhouse-java-ssl-client


