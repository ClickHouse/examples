defmodule IncidentRoom.Incidents do
  import Ecto.Query
  alias IncidentRoom.{Repo, Auth, Incident, Entry}

  @transitions %{
    "investigating" => ["monitoring"],
    "monitoring" => ["investigating", "resolved"],
    "resolved" => []
  }

  def valid_transition?(from, to), do: to in Map.get(@transitions, from, [])

  def valid_text?(text, limit),
    do:
      is_binary(text) and String.trim(text) != "" and length(String.to_charlist(text)) <= limit and
        not String.contains?(text, <<0>>)

  def list,
    do: Repo.all(from i in Incident, order_by: [desc: i.inserted_at, desc: i.id], limit: 100)

  def get(id), do: Repo.get(Incident, id)

  def timeline(id),
    do:
      Repo.all(
        from e in Entry,
          where: e.incident_id == ^id,
          order_by: [desc: e.inserted_at, desc: e.id],
          limit: 200,
          preload: :author
      )
      |> Enum.reverse()

  def open(token, attrs) when is_map(attrs) do
    result =
      Repo.transact(fn ->
        with %{} = user <- Auth.user(token),
             true <- Map.keys(attrs) == ["title"],
             true <- valid_text?(attrs["title"], 160),
             {:ok, incident} <-
               Repo.insert(Ecto.Changeset.change(%Incident{}, title: String.trim(attrs["title"]))),
             {:ok, _entry} <- entry(incident, user, "opened", "Incident opened") do
          {:ok, incident}
        else
          nil -> {:error, :unauthenticated}
          false -> {:error, :invalid_input}
          {:error, reason} -> {:error, reason}
        end
      end)

    broadcast(result)
  end

  def open(_, _), do: {:error, :invalid_input}

  def note(token, id, attrs) when is_map(attrs) do
    result =
      Repo.transact(fn ->
        with %{} = user <- Auth.user(token),
             true <- Map.keys(attrs) == ["body"],
             true <- valid_text?(attrs["body"], 2000),
             %{} = incident <- locked(id),
             false <- incident.status == "resolved",
             {:ok, _entry} <- entry(incident, user, "note", String.trim(attrs["body"])) do
          {:ok, incident}
        else
          nil -> {:error, :not_found_or_unauthenticated}
          true -> {:error, :resolved}
          false -> {:error, :invalid_input}
          {:error, reason} -> {:error, reason}
        end
      end)

    broadcast(result)
  end

  def note(_, _, _), do: {:error, :invalid_input}

  def transition(token, id, attrs) when is_map(attrs) do
    result =
      Repo.transact(fn ->
        with %{} = user <- Auth.user(token),
             true <- Enum.sort(Map.keys(attrs)) == ["status", "version"],
             %{} = incident <- locked(id),
             {:ok, version} <- version(attrs["version"]),
             :ok <- check_version(incident, version),
             true <- valid_transition?(incident.status, attrs["status"]),
             {:ok, changed} <-
               Repo.update(
                 Ecto.Changeset.change(incident,
                   status: attrs["status"],
                   version: incident.version + 1
                 )
               ),
             {:ok, _entry} <-
               entry(
                 changed,
                 user,
                 "status",
                 "Status changed from #{incident.status} to #{changed.status}"
               ) do
          {:ok, changed}
        else
          nil -> {:error, :not_found_or_unauthenticated}
          false -> {:error, :invalid_transition_or_input}
          {:error, reason} -> {:error, reason}
        end
      end)

    broadcast(result)
  end

  def transition(_, _, _), do: {:error, :invalid_input}

  defp locked(id), do: Repo.one(from i in Incident, where: i.id == ^id, lock: "FOR UPDATE")
  defp version(n) when is_integer(n) and n >= 0, do: {:ok, n}

  defp version(n) when is_binary(n) do
    case Integer.parse(n) do
      {version, ""} when version >= 0 -> {:ok, version}
      _ -> {:error, :invalid_version}
    end
  end

  defp version(_), do: {:error, :invalid_version}
  defp check_version(%{version: version}, version), do: :ok
  defp check_version(_, _), do: {:error, :stale_version}

  defp entry(incident, user, kind, body),
    do:
      Repo.insert(
        Ecto.Changeset.change(%Entry{},
          incident_id: incident.id,
          author_id: user.id,
          kind: kind,
          body: body
        )
      )

  defp broadcast({:ok, incident} = result) do
    Phoenix.PubSub.broadcast(IncidentRoom.PubSub, "incident:#{incident.id}", :committed)
    Phoenix.PubSub.broadcast(IncidentRoom.PubSub, "incidents", :committed)
    result
  end

  defp broadcast(error), do: error
end
