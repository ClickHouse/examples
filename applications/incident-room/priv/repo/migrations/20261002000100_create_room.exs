defmodule IncidentRoom.Repo.Migrations.CreateRoom do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :email, :string, null: false
      add :name, :string, null: false
      add :password_hash, :text, null: false
    end

    create unique_index(:users, [:email])

    create table(:sessions, primary_key: false) do
      add :token_hash, :binary, primary_key: true
      add :user_id, references(:users, type: :uuid), null: false
      add :expires_at, :utc_datetime_usec, null: false
    end

    create index(:sessions, [:expires_at])

    create table(:incidents, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :title, :string, size: 160, null: false
      add :status, :string, null: false, default: "investigating"
      add :version, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:incidents, :valid_status,
             check: "status IN ('investigating', 'monitoring', 'resolved')"
           )

    create constraint(:incidents, :valid_version, check: "version >= 0")
    create constraint(:incidents, :nonblank_title, check: "length(btrim(title)) > 0")

    create table(:entries, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :incident_id, references(:incidents, type: :uuid), null: false
      add :author_id, references(:users, type: :uuid), null: false
      add :kind, :string, null: false
      add :body, :text, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:entries, :valid_entry_kind, check: "kind IN ('opened', 'note', 'status')")
    create constraint(:entries, :bounded_body, check: "length(btrim(body)) BETWEEN 1 AND 2000")
    create index(:entries, [:incident_id, :inserted_at, :id])
    create index(:incidents, [:inserted_at, :id])
  end
end
