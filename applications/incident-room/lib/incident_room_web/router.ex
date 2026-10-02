defmodule IncidentRoomWeb.Router do
  use Phoenix.Router
  import Plug.Conn
  import Phoenix.Controller
  import Phoenix.LiveView.Router
  import IncidentRoomWeb.Auth

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {IncidentRoomWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:fetch_user)
  end

  pipeline :authenticated do
    plug(:require_user)
  end

  scope "/", IncidentRoomWeb do
    pipe_through(:browser)
    get("/sign-in", SessionController, :new)
    post("/sign-in", SessionController, :create)
    post("/sign-out", SessionController, :delete)
  end

  scope "/", IncidentRoomWeb do
    pipe_through([:browser, :authenticated])

    live_session :team, on_mount: [{IncidentRoomWeb.Auth, :required}] do
      live("/", IndexLive)
      live("/incidents/:id", RoomLive)
    end
  end
end
