alias IncidentRoom.{Repo, User, Incident, Entry}

for {id, email, name, env} <- [
      {"00000000-0000-0000-0000-000000000001", "casey@example.test", "Casey",
       "SEED_CASEY_PASSWORD"},
      {"00000000-0000-0000-0000-000000000002", "morgan@example.test", "Morgan",
       "SEED_MORGAN_PASSWORD"}
    ] do
  password = System.fetch_env!(env)
  if byte_size(password) < 16, do: raise("Seed passwords need at least 16 bytes")

  Repo.insert!(
    %User{id: id, email: email, name: name, password_hash: Bcrypt.hash_pwd_salt(password)},
    on_conflict: :nothing
  )
end

incident_id = "00000000-0000-0000-0000-000000000003"

Repo.insert!(%Incident{id: incident_id, title: "Elevated API errors", status: "investigating"},
  on_conflict: :nothing
)

Repo.insert!(
  %Entry{
    id: "00000000-0000-0000-0000-000000000004",
    incident_id: incident_id,
    author_id: "00000000-0000-0000-0000-000000000001",
    kind: "opened",
    body: "Incident opened"
  },
  on_conflict: :nothing
)
