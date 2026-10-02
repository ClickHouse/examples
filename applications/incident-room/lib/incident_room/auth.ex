defmodule IncidentRoom.Auth do
  import Ecto.Query
  alias IncidentRoom.{Repo, User, Session}
  @ttl_seconds 8 * 60 * 60

  def authenticate(email, password)
      when is_binary(email) and is_binary(password) and byte_size(email) <= 254 and
             byte_size(password) <= 128 do
    user = Repo.get_by(User, email: email |> String.trim() |> String.downcase())

    cond do
      user && Bcrypt.verify_pass(password, user.password_hash) ->
        {:ok, user}

      user ->
        {:error, :invalid_credentials}

      true ->
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  def authenticate(_, _), do: {:error, :invalid_credentials}

  def create_session(user) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    Repo.insert!(%Session{
      token_hash: hash(token),
      user_id: user.id,
      expires_at: DateTime.add(DateTime.utc_now(), @ttl_seconds, :second)
    })

    token
  end

  def user(token) when is_binary(token) and byte_size(token) <= 128 do
    Repo.one(
      from s in Session,
        join: u in User,
        on: u.id == s.user_id,
        where: s.token_hash == ^hash(token) and s.expires_at > ^DateTime.utc_now(),
        select: u
    )
  end

  def user(_), do: nil

  def delete_session(token) do
    Repo.delete_all(from s in Session, where: s.token_hash == ^hash(token))
    IncidentRoomWeb.Endpoint.broadcast(socket_id(token), "disconnect", %{})
  end

  def socket_id(token), do: "session:" <> Base.url_encode64(hash(token), padding: false)
  defp hash(token), do: :crypto.hash(:sha256, token)
end
