defmodule IncidentRoomWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :incident_room

  @session_options [
    store: :cookie,
    key: "_incident_room",
    signing_salt: "session-signing",
    encryption_salt: "session-encryption",
    same_site: "Lax",
    max_age: 8 * 60 * 60,
    http_only: true
  ]
  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false
  )

  plug(Plug.Static, at: "/", from: :incident_room, gzip: false, only: ~w(assets app.css))
  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    length: 16_384
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(:session)
  plug(IncidentRoomWeb.Router)

  defp session(conn, _) do
    options =
      Keyword.put(
        @session_options,
        :secure,
        Application.get_env(:incident_room, :cookie_secure, false)
      )

    Plug.Session.call(conn, Plug.Session.init(options))
  end
end
