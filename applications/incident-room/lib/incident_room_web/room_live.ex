defmodule IncidentRoomWeb.RoomLive do
  use Phoenix.LiveView, layout: false
  alias IncidentRoom.Incidents
  alias IncidentRoomWeb.Auth

  def mount(%{"id" => id}, _, socket) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        if connected?(socket), do: Phoenix.PubSub.subscribe(IncidentRoom.PubSub, "incident:#{id}")

        case Incidents.get(id) do
          nil ->
            {:ok, redirect(socket, to: "/")}

          incident ->
            {:ok,
             socket
             |> assign(
               incident: incident,
               timeline: Incidents.timeline(id),
               connected: connected?(socket),
               form: to_form(%{"body" => ""}, as: :note)
             )}
        end

      :error ->
        {:ok, redirect(socket, to: "/")}
    end
  end

  def handle_event("note", %{"note" => attrs}, socket),
    do:
      event(
        socket,
        fn -> Incidents.note(socket.assigns.session_token, socket.assigns.incident.id, attrs) end,
        true
      )

  def handle_event("transition", attrs, socket),
    do:
      event(socket, fn ->
        Incidents.transition(socket.assigns.session_token, socket.assigns.incident.id, attrs)
      end)

  def handle_event("draft", %{"note" => attrs}, socket) when is_map(attrs),
    do: {:noreply, assign(socket, form: to_form(Map.take(attrs, ["body"]), as: :note))}

  def handle_event(_, _, socket),
    do: {:noreply, put_flash(socket, :error, "Invalid update fields.")}

  defp event(socket, callback, clear_note \\ false) do
    if Auth.active?(socket) do
      case callback.() do
        {:ok, _} ->
          {:noreply,
           socket |> put_flash(:info, "Update saved.") |> reload() |> clear_form(clear_note)}

        {:error, :stale_version} ->
          {:noreply,
           socket
           |> reload()
           |> put_flash(
             :error,
             "The status changed. Review the current state before trying again."
           )}

        {:error, _} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "This update was not saved. Check the fields and current status."
           )}
      end
    else
      {:noreply, redirect(socket, to: "/sign-in")}
    end
  end

  defp clear_form(socket, true), do: assign(socket, form: to_form(%{"body" => ""}, as: :note))
  defp clear_form(socket, false), do: socket

  def handle_info(:committed, socket) do
    if Auth.active?(socket),
      do: {:noreply, reload(socket)},
      else: {:noreply, redirect(socket, to: "/sign-in")}
  end

  defp reload(socket),
    do:
      assign(socket,
        incident: Incidents.get(socket.assigns.incident.id),
        timeline: Incidents.timeline(socket.assigns.incident.id)
      )

  def render(assigns) do
    ~H"""
    <main class="page">
      <header>
        <a href="/" class="brand">← All incidents</a><div class="account">
          {@current_user.name}
          <form action="/sign-out" method="post">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} /><button class="quiet">Sign out</button>
          </form>
        </div>
      </header>
      <section class="incident-head">
        <div>
          <span class="eyebrow">SHARED INCIDENT</span><h1>{@incident.title}</h1><span
            id="incident-status"
            class={"status " <> @incident.status}
          >{String.capitalize(@incident.status)}</span><span class="muted">Version {@incident.version}</span>
        </div><span class="live-badge">{if @connected, do: "● Live room", else: "Connecting…"}</span>
      </section>
      <p :if={@flash["error"]} role="alert" class="error">{@flash["error"]}</p><p
        :if={@flash["info"]}
        role="status"
        class="notice"
      >
        {@flash["info"]}
      </p>
      <section class="workspace">
        <div>
          <h2>Timeline</h2><p class="muted">
            Latest 200 entries, in chronological order. Earlier entries remain in the database.
          </p><ol id="timeline" class="timeline">
            <li :for={entry <- @timeline} id={"entry-#{entry.id}"}>
              <div class="entry-meta">
                <strong>{entry.author.name}</strong><time>{Calendar.strftime(
                  entry.inserted_at,
                  "%d %b %H:%M:%S UTC"
                )}</time><span>{entry.kind}</span>
              </div><p>{entry.body}</p>
            </li>
          </ol>
        </div>
        <aside>
          <h2>Next update</h2><.form
            :if={@incident.status != "resolved"}
            for={@form}
            id="note-form"
            phx-submit="note"
            phx-change="draft"
          >
            <label>What does the team need to know?<textarea
              name="note[body]"
              rows="5"
              maxlength="2000"
              required
            >{@form[:body].value}</textarea></label><button>Add note</button>
          </.form><p :if={@incident.status == "resolved"} class="muted">
            This incident is resolved. The timeline stays available; new notes are closed.
          </p><div class="transitions">
            <h3>Change status</h3><button
              :for={status <- ["investigating", "monitoring", "resolved"]}
              :if={Incidents.valid_transition?(@incident.status, status)}
              phx-click="transition"
              phx-value-status={status}
              phx-value-version={@incident.version}
            >{String.capitalize(status)}</button>
          </div><p class="muted">Notes are permanent. Every status change adds a timeline entry.</p>
        </aside>
      </section>
    </main>
    """
  end
end
