defmodule IncidentRoomWeb.SessionController do
  use Phoenix.Controller, formats: [:html]
  import Plug.Conn
  alias IncidentRoom.Auth
  plug(:put_layout, false)
  def new(conn, _), do: render(conn, :new, error: nil)

  def create(conn, %{"session" => %{"email" => email, "password" => password} = attrs}) do
    if Enum.sort(Map.keys(attrs)) == ["email", "password"] do
      case Auth.authenticate(email, password) do
        {:ok, user} ->
          token = Auth.create_session(user)

          conn
          |> configure_session(renew: true)
          |> clear_session()
          |> put_session(:user_token, token)
          |> put_session(:live_socket_id, Auth.socket_id(token))
          |> redirect(to: "/")

        _ ->
          conn |> put_status(401) |> render(:new, error: "Check your email and password.")
      end
    else
      conn |> put_status(400) |> render(:new, error: "Invalid sign-in fields.")
    end
  end

  def create(conn, _),
    do: conn |> put_status(400) |> render(:new, error: "Enter your email and password.")

  def delete(conn, _) do
    if token = get_session(conn, :user_token), do: Auth.delete_session(token)
    conn |> clear_session() |> configure_session(drop: true) |> redirect(to: "/sign-in")
  end
end

defmodule IncidentRoomWeb.SessionHTML do
  use Phoenix.Component

  def new(assigns) do
    ~H"""
    <main class="sign-in">
      <span class="eyebrow">INCIDENT ROOM</span>
      <h1>A shared place to work through an incident.</h1>
      <p>Sign in with your team account to follow the timeline and add updates.</p>
      <p :if={@error} role="alert" class="error">{@error}</p>
      <form action="/sign-in" method="post">
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <label>Email<input name="session[email]" type="email" required autocomplete="username" /></label>
        <label>Password<input
          name="session[password]"
          type="password"
          required
          autocomplete="current-password"
        /></label>
        <button type="submit">Sign in</button>
      </form>
      <p class="muted">Team accounts are seeded by the person running this example.</p>
    </main>
    """
  end
end
