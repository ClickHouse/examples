import Config
cloud_test = System.get_env("CLOUD_TEST") == "true"
config :incident_room, :start_repo, config_env() != :test or cloud_test

if (config_env() != :test or cloud_test) and is_nil(System.get_env("PGHOST")),
  do: raise("PGHOST is required; configure the verified Cloud endpoint")

if host = System.get_env("PGHOST") do
  config :incident_room, IncidentRoom.Repo,
    hostname: host,
    port: String.to_integer(System.get_env("PGPORT", "5432")),
    database: System.get_env("PGDATABASE", "postgres"),
    username: System.fetch_env!("PGUSER"),
    password: System.fetch_env!("PGPASSWORD"),
    pool_size: 5,
    queue_target: 5_000,
    queue_interval: 5_000,
    ssl: [
      verify: :verify_peer,
      cacertfile: String.to_charlist(System.fetch_env!("PGSSLROOTCERT")),
      server_name_indication: String.to_charlist(host),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ],
    timeout: 30_000,
    connect_timeout: 15_000
end

origin = System.get_env("APP_ORIGIN", "http://127.0.0.1:4000")
uri = URI.parse(origin)

unless uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
         uri.userinfo == nil and uri.path in [nil, ""] and uri.query == nil and
         uri.fragment == nil,
       do: raise("APP_ORIGIN must be an http(s) origin")

secret =
  if config_env() == :test,
    do: System.get_env("SECRET_KEY_BASE", String.duplicate("test-only-", 8)),
    else: System.fetch_env!("SECRET_KEY_BASE")

if byte_size(secret) < 64, do: raise("SECRET_KEY_BASE must have at least 64 bytes")
config :incident_room, :cookie_secure, uri.scheme == "https"

config :incident_room, IncidentRoomWeb.Endpoint,
  secret_key_base: secret,
  server: System.get_env("PHX_SERVER") == "true",
  url: [host: uri.host, port: uri.port, scheme: uri.scheme],
  check_origin: [origin],
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT", "4000"))]
