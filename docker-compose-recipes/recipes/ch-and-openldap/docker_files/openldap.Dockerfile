FROM osixia/openldap:stable-arm64v8

ENV LDAP_ORGANISATION=clickhouse
ENV LDAP_DOMAIN=clickhouse.test
ENV LDAP_ADMIN_USERNAME=admin
ENV LDAP_ADMIN_PASSWORD=password
ENV LDAP_READONLY_USER=false
ENV LDAP_TLS=false
ENV LDAP_TLS_ENFORECE=false

COPY bootstrap/98-data.ldif /container/service/slapd/assets/config/bootstrap/ldif
COPY bootstrap/99-config.ldif /container/service/slapd/assets/config/bootstrap/ldif
