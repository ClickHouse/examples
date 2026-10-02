# Run with the schema owner's credentials, never the server's runtime role.
Ecto.Migrator.run(
  IncidentRoom.Repo,
  Application.app_dir(:incident_room, "priv/repo/migrations"),
  :up,
  all: true,
  prefix: "incident_room"
)
