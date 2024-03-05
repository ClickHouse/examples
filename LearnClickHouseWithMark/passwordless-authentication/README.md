# Passwordless authentication

Install ClickHouse

```bash
curl https://clickhouse.com/ | sh
```

Start ClickHouse Server

```bash
cp clickhouse clickhouse-server
cd clickhouse-server
./clickhouse server
```

Generate a private/public key (or use an existing one)

```bash
ssh-keygen \
  -t ed25519 \
  -C "youremail@gmail.com" \
  -f ssh-key/ch_key
```

View the public key

```bash
$ cat ssh-key/ch_key.pub
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK88RakXMF3nPNL4b4IT09StMJ2fFTSFdRigVfzh1fMw youremail@gmail.com
```

And copy the identifier i.e `AAAAC3NzaC1lZDI1NTE5AAAAIK88RakXMF3nPNL4b4IT09StMJ2fFTSFdRigVfzh1fMw` in this example.

Start ClickHouse Client

```bash
./clickhouse client -m
```

Create a user based on that key

```sql
CREATE USER alexey 
IDENTIFIED WITH ssh_key 
BY KEY 'AAAAC3NzaC1lZDI1NTE5AAAAIK88RakXMF3nPNL4b4IT09StMJ2fFTSFdRigVfzh1fMw'
TYPE 'ssh-ed25519';
```

Exit ClickHouse Client

```sql
exit;
```

And then connect with the Alexey user:

```sql
./clickhouse client \
    -q 'SELECT currentUser()' \
    --user alexey \
    --ssh-key-file ssh-key/ch_key
```

If you don't want to provide the location of the private key each time, you can specify it in the client config file. 
This lives at `~/.clickhouse-client/config.xml` and you need to add the following entry:

```xml
<config>
    <user>alexey</user>
    <ssh-key-file>/path/to/ssh-key/ch_key</ssh-key-file>
</config>
```

And then you can connect to ClickHouse Client like this:

```sql
./clickhouse client \
    -q 'SELECT currentUser()' \
    --user alexey
```

Or you could the contents to a `config.xml` file located elsewhere and pass in the path via the `-C` parameter.

```sql
./clickhouse client \
    -q 'SELECT currentUser()' \
    --user alexey \
    -C config.xml
```