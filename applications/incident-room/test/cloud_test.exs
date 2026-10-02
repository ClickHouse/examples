defmodule IncidentRoom.CloudTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import ExUnit.CaptureLog
  alias IncidentRoom.{Auth, Entry, Incidents, Repo, User}
  @moduletag :cloud

  setup do
    token = Auth.create_session(Repo.get_by!(User, email: "casey@example.test"))
    on_exit(fn -> Auth.delete_session(token) end)
    %{token: token}
  end

  test "same-endpoint Postgrex accepts verified TLS and rejects wrong CA and hostname" do
    assert %{rows: [[true]]} =
             Repo.query!("SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()")

    opts = Application.fetch_env!(:incident_room, Repo)
    rejected_tls(opts, :cacertfile, ~c"/etc/ssl/certs/ca-certificates.crt", "unknown_ca")

    rejected_tls(
      opts,
      :server_name_indication,
      ~c"wrong.example.invalid",
      "hostname_check_failed"
    )

    assert %{rows: [[1]]} = Repo.query!("SELECT 1")
  end

  test "runtime cannot run DDL, read migration history, or rewrite identity and timeline", %{
    token: token
  } do
    {:ok, incident} = Incidents.open(token, %{"title" => "Privilege checks"})
    id = Ecto.UUID.dump!(incident.id)

    for {sql, params} <- [
          {"CREATE TABLE incident_room.forbidden (id integer)", []},
          {"SELECT * FROM incident_room.schema_migrations", []},
          {"UPDATE incident_room.users SET name = name", []},
          {"UPDATE incident_room.entries SET body = body WHERE incident_id = $1", [id]},
          {"DELETE FROM incident_room.entries WHERE incident_id = $1", [id]}
        ] do
      assert {:error, %Postgrex.Error{postgres: %{code: :insufficient_privilege}}} =
               Repo.query(sql, params)
    end
  end

  test "concurrent expected-version transitions produce one committed status entry", %{
    token: token
  } do
    {:ok, incident} = Incidents.open(token, %{"title" => "Concurrent response"})

    results =
      1..2
      |> Enum.map(fn _ ->
        Task.async(fn ->
          Incidents.transition(token, incident.id, %{"status" => "monitoring", "version" => 0})
        end)
      end)
      |> Enum.map(&Task.await(&1, 30_000))

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, :stale_version}, &1)) == 1
    assert %{status: "monitoring", version: 1} = Incidents.get(incident.id)
    assert Enum.count(Incidents.timeline(incident.id), &(&1.kind == "status")) == 1
  end

  test "invalid transition and forged author roll back; resolved room rejects notes", %{
    token: token
  } do
    {:ok, incident} = Incidents.open(token, %{"title" => "Terminal room"})

    assert {:error, _} =
             Incidents.transition(token, incident.id, %{"status" => "resolved", "version" => 0})

    assert {:error, _} =
             Incidents.note(token, incident.id, %{
               "body" => "Forged",
               "author_id" => Ecto.UUID.generate()
             })

    assert [%{kind: "opened"}] = Incidents.timeline(incident.id)
    assert %{version: 0, status: "investigating"} = Incidents.get(incident.id)

    {:ok, _} =
      Incidents.transition(token, incident.id, %{"status" => "monitoring", "version" => 0})

    {:ok, _} = Incidents.transition(token, incident.id, %{"status" => "resolved", "version" => 1})
    assert {:error, :resolved} = Incidents.note(token, incident.id, %{"body" => "Too late"})
    assert length(Incidents.timeline(incident.id)) == 3
  end

  test "session identity is authoritative and revocation denies subsequent writes", %{
    token: token
  } do
    {:ok, incident} = Incidents.open(token, %{"title" => "Session authority"})
    {:ok, _} = Incidents.note(token, incident.id, %{"body" => "Verified author"})
    assert List.last(Incidents.timeline(incident.id)).author.email == "casey@example.test"
    Auth.delete_session(token)
    assert {:error, _} = Incidents.note(token, incident.id, %{"body" => "Revoked"})
    assert {:error, _} = Incidents.open(nil, %{"title" => "Signed out"})
    assert length(Incidents.timeline(incident.id)) == 2
  end

  test "bounded timeline retains the newest entry and Unicode bounds agree with SQL", %{
    token: token
  } do
    assert {:error, :invalid_input} =
             Incidents.open(token, %{"title" => String.duplicate("e\u0301", 81)})

    {:ok, incident} = Incidents.open(token, %{"title" => String.duplicate("e\u0301", 80)})
    author = Auth.user(token)
    now = DateTime.utc_now()

    rows =
      for n <- 1..205,
          do: %{
            id: Ecto.UUID.generate(),
            incident_id: incident.id,
            author_id: author.id,
            kind: "note",
            body: "Batch #{n}",
            inserted_at: DateTime.add(now, n, :microsecond)
          }

    Repo.insert_all(Entry, rows)
    timeline = Incidents.timeline(incident.id)
    assert length(timeline) == 200
    assert List.first(timeline).body == "Batch 6"
    assert List.last(timeline).body == "Batch 205"
    assert timeline == Enum.sort_by(timeline, &{&1.inserted_at, &1.id})
  end

  test "held database lock prevents writes and PubSub until committed", %{token: token} do
    {:ok, incident} = Incidents.open(token, %{"title" => "Commit boundary"})
    Phoenix.PubSub.subscribe(IncidentRoom.PubSub, "incident:#{incident.id}")
    parent = self()

    holder =
      Task.async(fn ->
        Repo.transact(fn ->
          Repo.one!(
            from i in IncidentRoom.Incident, where: i.id == ^incident.id, lock: "FOR UPDATE"
          )

          send(parent, :locked)

          receive do
            :release -> {:ok, :released}
          after
            15_000 -> {:error, :timeout}
          end
        end)
      end)

    assert_receive :locked, 15_000

    writer =
      Task.async(fn ->
        Incidents.transition(token, incident.id, %{"status" => "monitoring", "version" => 0})
      end)

    assert wait_for_blocking()
    refute_receive :committed, 200
    assert Task.yield(writer, 0) == nil
    send(holder.pid, :release)
    assert {:ok, :released} = Task.await(holder, 30_000)
    assert {:ok, %{version: 1}} = Task.await(writer, 30_000)
    assert_receive :committed, 5_000
    assert length(Incidents.timeline(incident.id)) == 2

    assert {:error, :stale_version} =
             Incidents.transition(token, incident.id, %{"status" => "resolved", "version" => 0})

    refute_receive :committed, 200
  end

  test "entry failure after status update rolls back state and emits no PubSub", %{token: token} do
    {:ok, incident} = Incidents.open(token, %{"title" => "Forced transaction rollback"})
    Phoenix.PubSub.subscribe(IncidentRoom.PubSub, "incident:#{incident.id}")
    opts = Application.fetch_env!(:incident_room, Repo)

    owner_opts =
      opts
      |> Keyword.put(:username, "incident_migration")
      |> Keyword.put(:password, System.fetch_env!("MIGRATION_PASSWORD"))
      |> Keyword.put(:pool_size, 1)

    {:ok, owner} = Postgrex.start_link(owner_opts)

    Postgrex.query!(
      owner,
      """
      CREATE FUNCTION incident_room.fail_entry_test() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'forced_timeline_failure' USING ERRCODE = '23514', CONSTRAINT = 'forced_timeline_failure';
      END;
      $$
      """,
      []
    )

    # UUID is generated by Ecto and contains only hex digits/hyphens. This DDL is
    # fixture-owner-only; production queries remain parameterized.
    Postgrex.query!(
      owner,
      """
      CREATE TRIGGER fail_entry_test BEFORE INSERT ON incident_room.entries
      FOR EACH ROW WHEN (NEW.incident_id = '#{incident.id}'::uuid AND NEW.kind = 'status')
      EXECUTE FUNCTION incident_room.fail_entry_test()
      """,
      []
    )

    try do
      try do
        Incidents.transition(token, incident.id, %{"status" => "monitoring", "version" => 0})
        flunk("Expected the timeline write to fail after the incident update")
      rescue
        error in [Postgrex.Error, Ecto.ConstraintError] ->
          assert Exception.message(error) =~ "forced_timeline_failure"
      end

      assert %{status: "investigating", version: 0} = Incidents.get(incident.id)
      assert [%{kind: "opened"}] = Incidents.timeline(incident.id)
      refute_receive :committed, 200
    after
      Postgrex.query!(owner, "DROP TRIGGER fail_entry_test ON incident_room.entries", [])
      Postgrex.query!(owner, "DROP FUNCTION incident_room.fail_entry_test()", [])
      GenServer.stop(owner, :normal, 30_000)
    end
  end

  defp wait_for_blocking do
    Enum.reduce_while(1..100, false, fn _, _ ->
      Repo.query!("SELECT pg_stat_clear_snapshot()")

      %{rows: [[count]]} =
        Repo.query!(
          "SELECT count(*) FROM pg_stat_activity WHERE usename = current_user AND cardinality(pg_blocking_pids(pid)) > 0"
        )

      if count > 0,
        do: {:halt, true},
        else:
          (
            Process.sleep(50)
            {:cont, false}
          )
    end)
  end

  defp rejected_tls(opts, key, value, expected) do
    ssl = Keyword.put(opts[:ssl], key, value)

    connection =
      opts
      |> Keyword.put(:ssl, ssl)
      |> Keyword.put(:backoff_type, :stop)
      |> Keyword.put(:pool_size, 1)
      |> Keyword.put(:max_restarts, 0)

    previous = Process.flag(:trap_exit, true)

    log =
      capture_log(fn ->
        {:ok, pid} = Postgrex.start_link(connection)
        monitor = Process.monitor(pid)
        assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 20_000
      end)

    Process.flag(:trap_exit, previous)
    assert log =~ expected
  end
end
