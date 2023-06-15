# ClickHouse cluster cluster_1S_2R

2 ClickHouse instances leveraging 3 dedicated ClickHouse Keepers

1 Shard with replication across clickhouse-01 and clickhouse-02

By default the version of ClickHouse used will be `latest`, and ClickHouse Keeper
will be `latest-alpine`.  You can specify specific versions by setting environment
variables before running `docker compose up`.

```bash
export CHVER=23.4
export CHKVER=23.4-alpine
docker compose up
```

This Docker compose file deploys a configuration matching [this
example in the documentation](https://clickhouse.com/docs/en/architecture/replication).
See the docs for information on terminology, configuration, and testing.

## Connecting with ClickHouse client

### clickhouse-01
```bash
docker compose exec clickhouse-01 clickhouse client --secure --port 9440
```

### clickhouse-02
```bash
docker compose exec clickhouse-02 clickhouse client --secure --port 9440
```

## Notes
- The standard HTTP and TCP ports for connecting clients are disabled, so use port 9440 or 8443.
- clickhouse client will need a config file that references the certificate in order to 
connect.  This is mounted at `/etc/clickhouse-client/config.xml` in `clickhouse-01` and `clickhouse-02`.
If you want to use it from elsewhere copy it and the files that it references.

## Using openssl to generate certificates
The steps below are from the [ClickHouse docs](https://clickhouse.com/docs/en/guides/sre/configuring-ssl).  The only difference is the names of the output files and nodes.

Note: You can use the certificates in this repo, these commands are here if you would like to generate your own.

```bash
openssl genrsa -out test_ca.key 2048
openssl req -x509 -subj "/CN=test CA" -nodes -key test_ca.key -days 1095 -out test_ca.crt
openssl x509 -in test_ca.crt -text
openssl req -newkey rsa:2048 -nodes -subj "/CN=clickhouse-01" -addext "subjectAltName = DNS:clickhouse-01" -keyout clickhouse-01.key -out clickhouse-01.csr
openssl req -newkey rsa:2048 -nodes -subj "/CN=clickhouse-02" -addext "subjectAltName = DNS:clickhouse-02" -keyout clickhouse-02.key -out clickhouse-02.csr
openssl req -newkey rsa:2048 -nodes -subj "/CN=clickhouse-keeper-03" -addext "subjectAltName = DNS:clickhouse-keeper-03" -keyout clickhouse-keeper-03.key -out clickhouse-keeper-03.csr
openssl req -newkey rsa:2048 -nodes -subj "/CN=clickhouse-keeper-02" -addext "subjectAltName = DNS:clickhouse-keeper-02" -keyout clickhouse-keeper-02.key -out clickhouse-keeper-02.csr
openssl req -newkey rsa:2048 -nodes -subj "/CN=clickhouse-keeper-01" -addext "subjectAltName = DNS:clickhouse-keeper-01" -keyout clickhouse-keeper-01.key -out clickhouse-keeper-01.csr
openssl x509 -req -in clickhouse-01.csr -out clickhouse-01.crt -CAcreateserial -CA test_ca.crt -CAkey test_ca.key -days 3650
openssl x509 -req -in clickhouse-02.csr -out clickhouse-02.crt -CAcreateserial -CA test_ca.crt -CAkey test_ca.key -days 3650
openssl x509 -req -in clickhouse-keeper-03.csr -out clickhouse-keeper-03.crt -CAcreateserial -CA test_ca.crt -CAkey test_ca.key -days 3650
openssl x509 -req -in clickhouse-keeper-02.csr -out clickhouse-keeper-02.crt -CAcreateserial -CA test_ca.crt -CAkey test_ca.key -days 3650
openssl x509 -req -in clickhouse-keeper-01.csr -out clickhouse-keeper-01.crt -CAcreateserial -CA test_ca.crt -CAkey test_ca.key -days 3650
openssl x509 -in clickhouse-01.crt -text -noout
openssl x509 -in clickhouse-02.crt -text -noout
openssl x509 -in clickhouse-keeper-01.crt -text -noout
openssl x509 -in clickhouse-keeper-02.crt -text -noout
openssl x509 -in clickhouse-keeper-03.crt -text -noout
openssl verify -CAfile test_ca.crt clickhouse-01.crt
openssl verify -CAfile test_ca.crt clickhouse-02.crt
openssl verify -CAfile test_ca.crt clickhouse-keeper-01.crt
openssl verify -CAfile test_ca.crt clickhouse-keeper-02.crt
openssl verify -CAfile test_ca.crt clickhouse-keeper-03.crt
mkdir fs/volumes/clickhouse-01/etc/certs
mkdir fs/volumes/clickhouse-02/etc/certs
mkdir fs/volumes/clickhouse-keeper-01/etc/certs
mkdir fs/volumes/clickhouse-keeper-02/etc/certs
mkdir fs/volumes/clickhouse-keeper-03/etc/certs
cp clickhouse-01.crt clickhouse-01.key test_ca.crt fs/volumes/clickhouse-01/etc/certs
cp clickhouse-02.crt clickhouse-02.key test_ca.crt fs/volumes/clickhouse-02/etc/certs
cp clickhouse-keeper-01.crt clickhouse-keeper-01.key test_ca.crt fs/volumes/clickhouse-keeper-01/etc/certs
cp clickhouse-keeper-02.crt clickhouse-keeper-02.key test_ca.crt fs/volumes/clickhouse-keeper-02/etc/certs
cp clickhouse-keeper-03.crt clickhouse-keeper-03.key test_ca.crt fs/volumes/clickhouse-keeper-03/etc/certs
```
