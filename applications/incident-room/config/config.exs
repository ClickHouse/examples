import Config
config :incident_room, ecto_repos: [IncidentRoom.Repo]
config :incident_room, IncidentRoom.Repo, migration_default_prefix: "incident_room"

config :incident_room, IncidentRoomWeb.Endpoint,
  url: [host: "127.0.0.1", port: 4000],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: IncidentRoomWeb.ErrorHTML], layout: false],
  pubsub_server: IncidentRoom.PubSub,
  live_view: [signing_salt: "live-room-signing"]

config :phoenix, :json_library, Jason

config :esbuild,
  version: "0.28.2",
  default: [
    args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :logger, level: :info
