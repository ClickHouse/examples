defmodule IncidentRoom.Application do
  use Application

  def start(_type, _args) do
    repo = if Application.get_env(:incident_room, :start_repo), do: [IncidentRoom.Repo], else: []
    children = repo ++ [{Phoenix.PubSub, name: IncidentRoom.PubSub}, IncidentRoomWeb.Endpoint]
    Supervisor.start_link(children, strategy: :one_for_one, name: IncidentRoom.Supervisor)
  end

  def config_change(changed, removed, _extra),
    do: IncidentRoomWeb.Endpoint.config_change(changed, removed)
end
