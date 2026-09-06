# ClickHouse authentication and role mapping with OpenLDAP

One ClickHouse server authenticates users against one OpenLDAP directory and maps their LDAP groups to ClickHouse roles. Three one-row tables make the permissions visible: Alice can read sales and shared data, Bob can read development and shared data, and Alice is denied development data. An incorrect password must be rejected.

This is a self-managed, local authentication lesson. LDAP and HTTP traffic are unencrypted; all credentials below are public development values. Only ClickHouse HTTP is published, at `127.0.0.1:18123`; LDAP is reachable only on the Compose network. Do not expose this stack or reuse these passwords on a shared host.

## Components, credentials, and requirements

The directory uses the community-maintained `chrroessner/openldap:2.6.14-r1` image, which publishes Linux amd64 and arm64 variants. It is not an official OpenLDAP-project container. This replaces the old ARM-only osixia image; the osixia-specific configuration bootstrap and phpLDAPadmin are no longer needed for the authentication walkthrough.

Use Docker Engine/Desktop or OrbStack with Docker Compose v2 and a POSIX shell. Allocate roughly 4 GiB of Docker memory, 2 CPUs, and several GiB of disk. No host LDAP tools, ClickHouse client, Python packages, or npm dependencies are required. Docker uses a Linux VM on macOS/Windows.

ClickHouse intentionally defaults to `${CHVER:-latest}`; export `CHVER` before starting to override it. OpenLDAP stays pinned to `2.6.14-r1`. Floating ClickHouse tags are not compatibility guarantees.

| Account | Password | Purpose |
| --- | --- | --- |
| `alice` | `password` | LDAP Sales + AllUsers roles |
| `bob` | `password` | LDAP Development + AllUsers roles |
| `ldapadmin` | `password` | LDAP Admins + AllUsers roles; management of the three demo databases' tables |
| `demo` | `local-example-password` | Local ClickHouse administration and fixture initialization |
| `cn=admin,dc=clickhouse,dc=test` | `local-admin-password` | OpenLDAP directory administrator |

Last manually verified: **2026-09-06**, ClickHouse **26.8.2.7**, OpenLDAP **2.6.14** (image **2.6.14-r1**), Linux **aarch64** on OrbStack (Docker 29.4.0 / Compose 5.1.2). From empty volumes, Alice/Bob authentication, mapped roles, permitted reads, incorrect-password rejection, and Alice's denied development read all passed. This is a single-platform manual check.

## Start and verify

From this directory, run the following complete block from empty volumes:

```sh
set -eu
docker compose up -d
q() {
  docker compose exec -T clickhouse clickhouse-client \
    --user "$1" --password "$2" --connect_timeout 3 --receive_timeout 10 \
    --max_execution_time 10 --query "$3"
}
# Wait for both LDAP authentication and SQL role/fixture initialization.
ready=false
attempt=0
while [ "$attempt" -lt 30 ]; do
  attempt=$((attempt + 1))
  if [ "$(q alice password 'SELECT message FROM sales_db.sample WHERE id = 1' 2>/dev/null)" = 'sales row' ]; then
    ready=true
    break
  fi
  sleep 2
done
[ "$ready" = true ]
q alice password 'SELECT version()'
[ "$(q alice password 'SELECT currentUser()')" = alice ]
[ "$(q alice password "SELECT has(currentRoles(), 'Sales') AND has(currentRoles(), 'AllUsers')")" = 1 ]
[ "$(q alice password 'SELECT message FROM other_data_db.sample WHERE id = 1')" = 'shared row' ]
[ "$(q bob password 'SELECT message FROM development_db.sample WHERE id = 1')" = 'development row' ]
[ "$(q bob password "SELECT has(currentRoles(), 'Development') AND has(currentRoles(), 'AllUsers')")" = 1 ]
if failure=$(q alice wrong-password 'SELECT 1' 2>&1); then
  echo 'ERROR: invalid credentials were accepted' >&2
  exit 1
fi
case "$failure" in
  *AUTHENTICATION_FAILED*) echo 'OK: incorrect password rejected' ;;
  *) printf 'Unexpected authentication error: %s\n' "$failure" >&2; exit 1 ;;
esac
if failure=$(q alice password 'SELECT * FROM development_db.sample' 2>&1); then
  echo 'ERROR: Alice read development data' >&2
  exit 1
fi
case "$failure" in
  *ACCESS_DENIED*) echo 'OK: Alice cannot read development data' ;;
  *) printf 'Unexpected authorization error: %s\n' "$failure" >&2; exit 1 ;;
esac
echo 'OK: Alice and Bob authenticate; LDAP groups supply the expected roles and reads'
```

OpenLDAP readiness authenticates the fixture's Alice account before ClickHouse starts (30 attempts, each limited to 5 seconds). The SQL readiness loop also has 30 attempts, with each query limited to 10 seconds plus a 3-second connection timeout. A failure exits nonzero; inspect `docker compose logs --tail=100` for details.

Expected output includes the actual ClickHouse version and all three `OK` lines. The negative checks require the expected ClickHouse error names, so a network error cannot masquerade as successful rejection. The verification is safe to repeat because it only reads the fixture.

## How the role mapping works

The [LDIF fixture](./docker_files/bootstrap/98-data.ldif) defines Users/Groups organizational units, three accounts, and `groupOfUniqueNames` groups. The base64 password values in LDIF are the text `password`, not encrypted secrets.

[ldap.xml](./config/ldap.xml) binds `cn={user_name},ou=Users,dc=clickhouse,dc=test`, finds groups containing the authenticated user's DN, and removes the `clickhouse_` prefix from each group name. For example, `clickhouse_Sales` maps to the existing SQL role `Sales`. Authentication caching is disabled for this lesson so each login is checked against LDAP.

[The SQL fixture](./clickhouse-init/00-fixture.sql) creates the roles and their grants. Sales and Development each have SELECT access only to their own database; AllUsers has SELECT access to `other_data_db`. Admins has SELECT, INSERT, and table creation/alteration/drop permissions in the three demonstration databases. LDAP stores credentials and group membership; ClickHouse stores the SQL roles and permissions.

To inspect Alice's entry with the client already inside the LDAP image:

```sh
docker compose exec -T openldap ldapsearch -x -o nettimeout=3 \
  -H ldap://127.0.0.1:389 -D 'cn=alice,ou=Users,dc=clickhouse,dc=test' \
  -w password -b 'ou=Users,dc=clickhouse,dc=test' '(cn=alice)' cn
```

## Stop, rerun, and reset

`docker compose stop` preserves both named volumes, and `docker compose up -d` resumes the stack. For an empty-state rerun:

```sh
docker compose down -v --remove-orphans
```

This is destructive: it removes the LDAP directory and the ClickHouse data/access state. The checked-in LDIF, SQL, and XML remain. Repeat the start/verify block; bootstrap runs on the fresh volumes.

## ClickHouse Cloud counterpart and documentation

This LDAP configuration is a **self-managed ClickHouse** feature and is not an LDAP endpoint configuration for ClickHouse Cloud. For Cloud, use its supported authentication and access-management options, with SQL users/roles for database permissions; do not point a Cloud service at this local LDAP container.

- [ClickHouse LDAP authentication and role mapping](https://clickhouse.com/docs/guides/sre/configuring-ldap)
- [ClickHouse access control](https://clickhouse.com/docs/operations/access-rights)
- [ClickHouse Cloud access management](https://clickhouse.com/docs/cloud/security/cloud-access-management/overview)
- [OpenLDAP image maintainer documentation and source](https://github.com/croessner/docker-openldap)
- [OpenLDAP administration guide](https://www.openldap.org/doc/admin26/)
