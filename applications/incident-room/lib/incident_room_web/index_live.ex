defmodule IncidentRoomWeb.IndexLive do
  use Phoenix.LiveView, layout: false
  alias IncidentRoom.{Incidents, Auth}

  def mount(_, _, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(IncidentRoom.PubSub, "incidents")

    {:ok,
     assign(socket, incidents: Incidents.list(), form: to_form(%{"title" => ""}, as: :incident))}
  end

  def handle_event("open", %{"incident" => attrs}, socket) do
    case Incidents.open(socket.assigns.session_token, attrs) do
      {:ok, incident} ->
        {:noreply, push_navigate(socket, to: "/incidents/#{incident.id}")}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Enter a title up to 160 characters; use only the title field."
         )}
    end
  end

  def handle_event(_, _, socket),
    do: {:noreply, put_flash(socket, :error, "Invalid update fields.")}

  def handle_info(:committed, socket) do
    if Auth.user(socket.assigns.session_token),
      do: {:noreply, assign(socket, incidents: Incidents.list())},
      else: {:noreply, redirect(socket, to: "/sign-in")}
  end

  def render(assigns) do
    ~H"""
    <main class="page">
      <header>
        <a href="/" class="brand">Incident Room</a><div class="account">
          {@current_user.name}
          <form action="/sign-out" method="post">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} /><button class="quiet">Sign out</button>
          </form>
        </div>
      </header>
      <section class="intro">
        <span class="eyebrow">TEAM INCIDENTS</span><h1>Keep the response in one room.</h1><p>
          Open an incident, add what you know, and follow the team's progress.
        </p>
      </section>
      <p :if={@flash["error"]} role="alert" class="error">{@flash["error"]}</p>
      <.form for={@form} id="open-incident" phx-submit="open" class="open-form">
        <input name="incident[title]" placeholder="What is happening?" maxlength="160" required /><button>Open incident</button>
      </.form>
      <section class="rooms">
        <a :for={incident <- @incidents} href={"/incidents/#{incident.id}"} class="room-card"><div>
          <span class={"status " <> incident.status}>{String.capitalize(incident.status)}</span><h2>
            {incident.title}
          </h2>
        </div><span class="muted">View timeline →</span></a><p :if={@incidents == []} class="empty">
          No incidents yet. Open the first room above.
        </p>
      </section>
      <footer>One shared team · latest 100 incidents</footer>
    </main>
    """
  end
end
