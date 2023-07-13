# ClickHouse and OpenLDAP

1 single ClickHouse Instance configured with 1 OpenLDAP instance

The OpenLdap server in use has the [following users and groups](./docker_files/bootstrap/98-data.ldif):

```ldif
dn: ou=Groups,dc=clickhouse,dc=test
changetype: add
objectclass: organizationalUnit
ou: Groups

dn: ou=Users,dc=clickhouse,dc=test
changetype: add
objectclass: organizationalUnit
ou: Users

# GROUPS used for role mapping

# Admins
dn: cn=clickhouse_Admins,ou=Groups,dc=clickhouse,dc=test
changetype: add
cn: clickhouse_Admins
objectclass: groupOfUniqueNames
uniqueMember: cn=ldapadmin,ou=Users,dc=clickhouse,dc=test

# Development
dn: cn=clickhouse_Development,ou=Groups,dc=clickhouse,dc=test
changetype: add
cn: clickhouse_Development
objectclass: groupOfUniqueNames
uniqueMember: cn=bob,ou=Users,dc=clickhouse,dc=test

# Sales
dn: cn=clickhouse_Sales,ou=Groups,dc=clickhouse,dc=test
changetype: add
cn: clickhouse_Sales
objectclass: groupOfUniqueNames
uniqueMember: cn=alice,ou=Users,dc=clickhouse,dc=test

# AllUsers
dn: cn=clickhouse_AllUsers,ou=Groups,dc=clickhouse,dc=test
changetype: add
cn: clickhouse_AllUsers
objectclass: groupOfUniqueNames
uniqueMember: cn=bob,ou=Users,dc=clickhouse,dc=test
uniqueMember: cn=alice,ou=Users,dc=clickhouse,dc=test
uniqueMember: cn=ldapadmin,ou=Users,dc=clickhouse,dc=test

#USERS

#alice (Sales)
dn: cn=alice,ou=Users,dc=clickhouse,dc=test
changetype: add
objectclass: inetOrgPerson
cn: alice
givenname: alice
sn: alice
displayname: Alice
mail: alice@clickhouse.test
userPassword:: cGFzc3dvcmQ=      

#bob (Development)
dn: cn=bob,ou=Users,dc=clickhouse,dc=test
changetype: add
objectclass: inetOrgPerson
cn: bob
givenname: bob
sn: bob
displayname: Bob
mail: bob@clickhouse.test
userPassword:: cGFzc3dvcmQ=

#ldapadmin 
dn: cn=ldapadmin,ou=Users,dc=clickhouse,dc=test
changetype: add
objectclass: inetOrgPerson
cn: ldapadmin
givenname: ldapadmin
sn: LDAPAdmin
displayname: LDAP Admin User
mail: ldapadmin@clickhouse.test
userPassword:: cGFzc3dvcmQ=

```

These roles are mapped respectively in ClickHouse through the [db](./fs/volumes/clickhouse/docker-entrypoint-initdb.d/1_create_ldap_dbs.sh) and [roles](./fs/volumes/clickhouse/docker-entrypoint-initdb.d/2_create_ldap_roles.sh) configs:

```sql
CREATE DATABASE IF NOT EXISTS sales_db;
CREATE DATABASE IF NOT EXISTS development_db;
CREATE DATABASE IF NOT EXISTS other_data_db;
CREATE ROLE IF NOT EXISTS Admins;
GRANT ALL ON *.* TO Admins;
CREATE ROLE IF NOT EXISTS Sales;
GRANT ALL ON sales_db.* TO Sales;
CREATE ROLE IF NOT EXISTS Development;
GRANT ALL ON development_db.* TO Development;
CREATE ROLE IF NOT EXISTS AllUsers;
GRANT SELECT ON *.* TO AllUsers;
```

the rest of configuration to define the LDAP server and map the LDAP groups to ClickHouse roles is defined in clickhouse [config.xml](./fs/volumes/clickhouse/etc/clickhouse-server/config.d/config.xml):

```xml
<ldap_servers>
        <openldap>
            <host>openldap</host>
            <port>389</port>
            <bind_dn>cn={user_name},ou=Users,dc=clickhouse,dc=test</bind_dn>
            <user_dn_detection>
                <base_dn>ou=Users,dc=clickhouse,dc=test</base_dn>
                <search_filter>(&amp;(objectClass=inetOrgPerson)(cn={user_name}))</search_filter>
            </user_dn_detection>
            <verification_cooldown>300</verification_cooldown>
            <enable_tls>no</enable_tls>
        </openldap>
    </ldap_servers>
    <user_directories>
        <ldap>
            <server>openldap</server>
            <role_mapping>
                <base_dn>ou=Groups,dc=clickhouse,dc=test</base_dn>
                <attribute>cn</attribute>
                <scope>subtree</scope>
                <search_filter>(&amp;(objectClass=groupOfUniqueNames)(uniqueMember={user_dn}))</search_filter>
                <prefix>clickhouse_</prefix>
            </role_mapping>
        </ldap>
    </user_directories>
```

All LDAP users are using password: `password`

You can validate the LDAP schema using PhpLDAPAdmin UI at http://localhost

Login DN: `cn=ldapadmin,ou=Users,dc=clickhouse,dc=test`

Password: `password`

Or by running on your host `ldapsearch` command, example:

If you do not have `ldapsearch` on your host you can run it from the openldap container:

```
ldapsearch  -D 'cn=bob,ou=Users,dc=clickhouse,dc=test' -b'dc=clickhouse,dc=test' -H ldap://localhost:389 -w password
```

When authenticating with user `bob` and `alice` in ClickHouse, you will see in the ClickHouse server trace logs they will receive different ClickHouse roles assigned, based on their LDAP group membership:

```
//bob - Development

2023.07.11 16:09:42.170685 [ 312 ] {} <Debug> TCPHandler: Connected ClickHouse client version 23.2.0, revision: 54461, user: bob.
2023.07.11 16:09:42.171241 [ 312 ] {} <Debug> TCP-Session: 161ba538-b6c2-48bc-b194-3196fed67124 Authenticating user 'bob' from 172.21.0.1:33822
2023.07.11 16:09:42.179125 [ 312 ] {} <Debug> TCP-Session: 161ba538-b6c2-48bc-b194-3196fed67124 Authenticated with global context as user 0640083d-fdab-3b41-2d9a-19f1eac6f19f
2023.07.11 16:09:42.179185 [ 312 ] {} <Warning> TCPHandler: Using deprecated interserver protocol because the client is too old. Consider upgrading all nodes in cluster. (skipped 1 similar messages)
2023.07.11 16:09:42.181927 [ 312 ] {} <Debug> TCP-Session: 161ba538-b6c2-48bc-b194-3196fed67124 Creating session context with user_id: 0640083d-fdab-3b41-2d9a-19f1eac6f19f
2023.07.11 16:09:42.182675 [ 312 ] {} <Trace> ContextAccess (bob): Current_roles: Development, AllUsers, enabled_roles: Development, AllUsers


//alice - Sales

2023.07.11 16:10:27.820959 [ 312 ] {} <Debug> TCPHandler: Connected ClickHouse client version 23.2.0, revision: 54461, user: alice.
2023.07.11 16:10:27.821076 [ 312 ] {} <Debug> TCP-Session: b0043532-e590-4421-8ce7-2885a7cc32e3 Authenticating user 'alice' from 172.21.0.1:56200
2023.07.11 16:10:27.831634 [ 312 ] {} <Debug> TCP-Session: b0043532-e590-4421-8ce7-2885a7cc32e3 Authenticated with global context as user 9f402224-724b-a201-241a-20358865cab0
2023.07.11 16:10:27.831712 [ 312 ] {} <Warning> TCPHandler: Using deprecated interserver protocol because the client is too old. Consider upgrading all nodes in cluster. (skipped 1 similar messages)
2023.07.11 16:10:27.837146 [ 312 ] {} <Debug> TCP-Session: b0043532-e590-4421-8ce7-2885a7cc32e3 Creating session context with user_id: 9f402224-724b-a201-241a-20358865cab0
2023.07.11 16:10:27.837589 [ 312 ] {} <Trace> ContextAccess (alice): Current_roles: AllUsers, Sales, enabled_roles: AllUsers, Sales
```


The documentation for ClickHouse and LDAP is available in the [ClickHouse documentation](https://clickhouse.com/docs/en/guides/sre/configuring-ldap).

If you would like to contribute to this example, please open an issue in this repo.  Thanks in advance for your contribution!
