defmodule IncidentRoomWeb.Auth do
  import Plug.Conn
  alias IncidentRoom.Auth

  def fetch_user(conn, _) do
    Plug.Conn.assign(conn, :current_user, Auth.user(get_session(conn, :user_token)))
  end

  def require_user(%{assigns: %{current_user: nil}} = conn, _),
    do: conn |> Phoenix.Controller.redirect(to: "/sign-in") |> halt()

  def require_user(conn, _), do: conn

  def on_mount(:required, _params, session, socket) do
    token = session["user_token"]

    case Auth.user(token) do
      nil -> {:halt, Phoenix.LiveView.redirect(socket, to: "/sign-in")}
      user -> {:cont, Phoenix.Component.assign(socket, current_user: user, session_token: token)}
    end
  end

  def active?(socket), do: Auth.user(socket.assigns.session_token) != nil
end
