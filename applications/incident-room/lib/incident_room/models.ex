defmodule IncidentRoom.User do
  use Ecto.Schema
  @schema_prefix "incident_room"
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users" do
    field :email, :string
    field :name, :string
    field :password_hash, :string, redact: true
  end
end

defmodule IncidentRoom.Session do
  use Ecto.Schema
  @schema_prefix "incident_room"
  @primary_key {:token_hash, :binary, autogenerate: false}
  schema "sessions" do
    belongs_to :user, IncidentRoom.User, type: :binary_id
    field :expires_at, :utc_datetime_usec
  end
end

defmodule IncidentRoom.Incident do
  use Ecto.Schema
  @schema_prefix "incident_room"
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "incidents" do
    field :title, :string
    field :status, :string, default: "investigating"
    field :version, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end
end

defmodule IncidentRoom.Entry do
  use Ecto.Schema
  @schema_prefix "incident_room"
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "entries" do
    belongs_to :incident, IncidentRoom.Incident, type: :binary_id
    belongs_to :author, IncidentRoom.User, type: :binary_id
    field :kind, :string
    field :body, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
