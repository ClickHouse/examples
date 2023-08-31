FROM clickhouse/clickhouse-server

USER clickhouse

RUN mkdir /etc/clickhouse-server/certs

WORKDIR /etc/clickhouse-server/certs

# generate private key for root CA
RUN openssl genrsa  -out clickhouse_test_CA.key 2048

# generate root cert clickhouse_test_CA.pem
RUN openssl req -x509 -new -nodes -subj '/CN=Test CA/O=ClickHouse' -key clickhouse_test_CA.key -sha256 -days 1825 -out clickhouse_test_CA.pem

# generate private key for nodes
RUN openssl genrsa -out clickhouse-01.key 2048

# create CSR 
RUN openssl req -new -key clickhouse-01.key -subj '/CN=Test ClickHouse-01/O=ClickHouse' -out clickhouse-01.csr

# create an X509 V3 certificate extension config file (clickhouse-01.ext), which is used to define the Subject Alternative Name (SAN) for the certificate
RUN cat <<EOT >> clickhouse-01.ext 
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = clickhouse-01
DNS.2 = localhost
IP.1 = 127.0.0.1
IP.2 = 192.168.50.1
EOT

# run the command to create the certificate: using our CSR, the CA private key, the CA certificate, and the config file:
RUN openssl x509 -req -in clickhouse-01.csr -CA clickhouse_test_CA.pem -CAkey clickhouse_test_CA.key -CAcreateserial -out clickhouse-01.crt -days 825 -sha256 -extfile clickhouse-01.ext

# We now have 7 files:
# clickhouse-01.key (the private key)
# clickhouse-01.ext (the extensions like subjectAltNames to add to the CSR)
# clickhouse-01.csr (the certificate signing request for this node, or csr file)
# clickhouse-01.crt (the root CA signed certificate for this node). 
# clickhouse_test_CA.key (the private key)
# clickhouse_test_CA.srl
# clickhouse_test_CA.pem (the root CA certificate). 

# remove private keys and CSR
# RUN rm clickhouse-01.csr clickhouse-01.ext clickhouse_test_CA.key clickhouse_test_CA.srl 
#

# TEST with curl
# ➜  ~ curl -v https://localhost:8443
# *   Trying 127.0.0.1:8443...
# * Connected to localhost (127.0.0.1) port 8443 (#0)
# * ALPN: offers h2,http/1.1
# * (304) (OUT), TLS handshake, Client hello (1):
# *  CAfile: /etc/ssl/cert.pem
# *  CApath: none
# * (304) (IN), TLS handshake, Server hello (2):
# * (304) (OUT), TLS handshake, Client hello (1):
# * (304) (IN), TLS handshake, Server hello (2):
# * (304) (IN), TLS handshake, Unknown (8):
# * (304) (IN), TLS handshake, Request CERT (13):
# * (304) (IN), TLS handshake, Certificate (11):
# * SSL certificate problem: unable to get local issuer certificate
# * Closing connection 0
# curl: (60) SSL certificate problem: unable to get local issuer certificate
# More details here: https://curl.se/docs/sslcerts.html

# curl failed to verify the legitimacy of the server and therefore could not
# establish a secure connection to it. To learn more about this situation and
# how to fix it, please visit the web page mentioned above.
# ➜  ~ docker ps
# CONTAINER ID   IMAGE               COMMAND            CREATED       STATUS       PORTS                                                                                                              NAMES
# 119073bb2f8c   ch-ssl-clickhouse   "/entrypoint.sh"   2 hours ago   Up 2 hours   127.0.0.1:8123->8123/tcp, 127.0.0.1:8443->8443/tcp, 127.0.0.1:9000->9000/tcp, 127.0.0.1:9440->9440/tcp, 9009/tcp   clickhouse
# ➜  ~ docker cp 119073bb2f8c:/etc/clickhouse-server/certs/clickhouse_test_CA.pem .
# Successfully copied 3.07kB to /Users/abonuccelli/.
# ➜  ~ curl -v https://localhost:8443 --cacert clickhouse_test_CA.pem
# *   Trying 127.0.0.1:8443...
# * Connected to localhost (127.0.0.1) port 8443 (#0)
# * ALPN: offers h2,http/1.1
# * (304) (OUT), TLS handshake, Client hello (1):
# *  CAfile: clickhouse_test_CA.pem
# *  CApath: none
# * (304) (IN), TLS handshake, Server hello (2):
# * (304) (OUT), TLS handshake, Client hello (1):
# * (304) (IN), TLS handshake, Server hello (2):
# * (304) (IN), TLS handshake, Unknown (8):
# * (304) (IN), TLS handshake, Request CERT (13):
# * (304) (IN), TLS handshake, Certificate (11):
# * (304) (IN), TLS handshake, CERT verify (15):
# * (304) (IN), TLS handshake, Finished (20):
# * (304) (OUT), TLS handshake, Certificate (11):
# * (304) (OUT), TLS handshake, Finished (20):
# * SSL connection using TLSv1.3 / AEAD-CHACHA20-POLY1305-SHA256
# * ALPN: server did not agree on a protocol. Uses default.
# * Server certificate:
# *  subject: CN=Test ClickHouse-01; O=ClickHouse
# *  start date: Aug 29 11:04:44 2023 GMT
# *  expire date: Dec  1 11:04:44 2025 GMT
# *  subjectAltName: host "localhost" matched cert's "localhost"
# *  issuer: CN=Test CA; O=ClickHouse
# *  SSL certificate verify ok.
# * using HTTP/1.x
# > GET / HTTP/1.1
# > Host: localhost:8443
# > User-Agent: curl/7.88.1
# > Accept: */*
# >
# < HTTP/1.1 200 OK
# < Date: Tue, 29 Aug 2023 12:40:09 GMT
# < Connection: Keep-Alive
# < Content-Type: text/html; charset=UTF-8
# < Transfer-Encoding: chunked
# < Keep-Alive: timeout=3
# < X-ClickHouse-Summary: {"read_rows":"0","read_bytes":"0","written_rows":"0","written_bytes":"0","total_rows_to_read":"0","result_rows":"0","result_bytes":"0"}
# <
# Ok.
# * Connection #0 to host localhost left intact
