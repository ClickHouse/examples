FROM osixia/openldap:stable-arm64v8

ENV LDAP_DOMAIN="clickhouse.test"

COPY bootstrap.ldif /container/service/slapd/assets/config/bootstrap/ldif/50-bootstrap.ldif
