#!/usr/bin/env bash

kafka_connector_version=`curl -s https://github.com/ClickHouse/clickhouse-kafka-connect/releases/latest -L | grep '<title>' | egrep -o 'v[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+'`

target="/opt/chkc"

mkdir -pv $target

wget https://github.com/ClickHouse/clickhouse-kafka-connect/releases/download/$kafka_connector_version/clickhouse-kafka-connect-$kafka_connector_version.zip -O /tmp/connector.zip && unzip /tmp/connector.zip -d ${target} && rm /tmp/connector.zip

cp -v /opt/clickhouse-kafka-connector/config.json ${target}/clickhouse-kafka-connect-${kafka_connector_version}/

find ${target}

cd ${target}/clickhouse-kafka-connect-${kafka_connector_version}/

pwd 

java -version

mkdir ${target}/clickhouse-kafka-connect-${kafka_connector_version}/META-INF

echo "Main-Class: com.clickhouse.kafka.connect.ClickHouseSinkConnector" > ${target}/clickhouse-kafka-connect-${kafka_connector_version}/META-INF/MANIFEST.MF

find ${target}/clickhouse-kafka-connect-${kafka_connector_version}/

java -jar ${target}/clickhouse-kafka-connect-${kafka_connector_version}/lib/clickhouse-kafka-connect-${kafka_connector_version}-confluent.jar


