using System.Net;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Text.Json;
using CapacityBoard.Data;
using CapacityBoard.Domain;
using Dapper;
using Npgsql;

public static class CloudChecks
{
    private static void Check(bool condition, string detail)
    {
        if (!condition) throw new Exception(detail);
    }
    private static async Task Rejected(Func<Task> operation, string code)
    {
        try { await operation(); }
        catch (BoardError error) when (error.Code == code) { return; }
        throw new Exception($"Expected {code}");
    }
    private static async Task SqlRejected(NpgsqlDataSource source, string sql, string state)
    {
        await using var conn = await source.OpenConnectionAsync();
        try { await conn.ExecuteAsync(new CommandDefinition(sql, commandTimeout: 4)); }
        catch (PostgresException error) when (error.SqlState == state) { return; }
        throw new Exception($"Expected SQLSTATE {state}");
    }
    private static string Describe(BoardSnapshot value) => JsonSerializer.Serialize(value);

    public static async Task Run()
    {
        await using var source = Database.Create("capacity_app");
        var ownerBuilder = new NpgsqlConnectionStringBuilder(source.ConnectionString)
        {
            Username = "capacity_migration",
            Password = Environment.GetEnvironmentVariable("MIGRATION_PASSWORD"),
            ApplicationName = "capacity-board-owner"
        };
        await using var owner = NpgsqlDataSource.Create(ownerBuilder.ConnectionString);
        var observerBuilder = new NpgsqlConnectionStringBuilder(source.ConnectionString)
        {
            Username = Environment.GetEnvironmentVariable("ADMIN_USER"),
            Password = Environment.GetEnvironmentVariable("ADMIN_PASSWORD"),
            ApplicationName = "capacity-board-observer"
        };
        await using var observer = NpgsqlDataSource.Create(observerBuilder.ConnectionString);
        using var repository = new BoardRepository(source);
        async Task Sql(string sql)
        {
            await using var conn = await owner.OpenConnectionAsync();
            await conn.ExecuteAsync(new CommandDefinition(sql, commandTimeout: 4));
        }
        async Task<int> Scalar(string sql)
        {
            await using var conn = await owner.OpenConnectionAsync();
            return await conn.ExecuteScalarAsync<int>(new CommandDefinition(sql, commandTimeout: 4));
        }
        async Task Reset()
        {
            await Sql("DELETE FROM capacity_board.saves; DELETE FROM capacity_board.work_items; UPDATE capacity_board.boards SET revision=1;");
        }
        var initial = await repository.ReadAsync();
        Check(initial.Id == Allocation.BoardId && initial.Total == 9 && initial.Revision == 1, "seed mapping");
        var request = new SaveRequest(Guid.NewGuid(), 1, [new WorkItem(Guid.NewGuid(), " Café ✨ ", 4)]);
        var saved = await repository.SaveAsync(request);
        Check(saved.Revision == 2 && saved.Items[0].Name == "Café ✨" && saved.Items[0].Points == 4, "typed UUID/int mapping");
        var empty = await repository.SaveAsync(new SaveRequest(Guid.NewGuid(), 2, []));
        Check(empty.Items.Length == 0 && empty.Revision == 3 && empty.Total == 0, "left-join nullable mapping");
        var replay = await repository.SaveAsync(request);
        Check(Describe(replay) == Describe(saved), "retained original result after a later save");
        await Rejected(() => repository.SaveAsync(request with { Items = [request.Items[0] with { Points = 5 }] }), "operation_conflict");
        await using (var conn = await source.OpenConnectionAsync())
        {
            var timestamp = await conn.ExecuteScalarAsync<DateTime>("SELECT created_at FROM capacity_board.saves ORDER BY revision LIMIT 1");
            Check(timestamp.Kind == DateTimeKind.Utc, "timestamptz UTC mapping");
        }
        Console.WriteLine("PASS typed UUID/int/null/UTC mappings and immutable exact replay");

        var rollback = new SaveRequest(Guid.NewGuid(), empty.Revision,
            [new WorkItem(Guid.NewGuid(), "First inserted", 2), new WorkItem(Guid.NewGuid(), "Reject second", 3)]);
        await Sql("""
            CREATE FUNCTION capacity_board.reject_child() RETURNS trigger LANGUAGE plpgsql AS $$
            BEGIN
                IF NEW.name = 'Reject second' THEN RAISE EXCEPTION 'test-only rejection' USING ERRCODE='23514'; END IF;
                RETURN NEW;
            END $$;
            CREATE TRIGGER test_child BEFORE INSERT ON capacity_board.work_items FOR EACH ROW EXECUTE FUNCTION capacity_board.reject_child();
            """);
        try
        {
            try { await repository.SaveAsync(rollback); throw new Exception("failure missing"); }
            catch (PostgresException error) when (error.SqlState == "23514") { }
            Check(Describe(await repository.ReadAsync()) == Describe(empty), "child replacement rollback");
            Check(await Scalar("SELECT count(*)::int FROM capacity_board.saves") == 2, "audit unchanged");
        }
        finally { await Sql("DROP TRIGGER test_child ON capacity_board.work_items; DROP FUNCTION capacity_board.reject_child();"); }
        var recovered = await repository.SaveAsync(rollback);
        Check(recovered.Revision == 4 && recovered.Items.Length == 2, "later valid request after failure");
        Console.WriteLine("PASS second-child failure rolls back replacement and preserves revision/audit; recovery");

        var deferred = new SaveRequest(Guid.NewGuid(), 4, [new WorkItem(Guid.NewGuid(), "Deferred commit", 6)]);
        await Sql("""
            CREATE FUNCTION capacity_board.reject_commit() RETURNS trigger LANGUAGE plpgsql AS $$
            BEGIN RAISE EXCEPTION 'test-only deferred rejection' USING ERRCODE='23514'; END $$;
            CREATE CONSTRAINT TRIGGER test_commit AFTER INSERT ON capacity_board.saves DEFERRABLE INITIALLY DEFERRED
            FOR EACH ROW EXECUTE FUNCTION capacity_board.reject_commit();
            """);
        try
        {
            try { await repository.SaveAsync(deferred); throw new Exception("commit failure missing"); }
            catch (PostgresException error) when (error.SqlState == "23514") { }
            Check(Describe(await repository.ReadAsync()) == Describe(recovered), "commit rollback full snapshot");
            Check(await Scalar("SELECT count(*)::int FROM capacity_board.saves") == 3, "deferred audit rollback");
        }
        finally { await Sql("DROP TRIGGER test_commit ON capacity_board.saves; DROP FUNCTION capacity_board.reject_commit();"); }
        Check((await repository.SaveAsync(deferred)).Revision == 5, "same UUID after rolled back COMMIT");
        Console.WriteLine("PASS actual deferred COMMIT failure rolls back children/revision/audit and same-UUID recovery");

        // Warm only the test pool, so both independent sessions are available before holding the parent.
        var warm = await Task.WhenAll(source.OpenConnectionAsync().AsTask(), source.OpenConnectionAsync().AsTask());
        foreach (var connection in warm) await connection.DisposeAsync();
        await using (var holder = await owner.OpenConnectionAsync())
        await using (var transaction = await holder.BeginTransactionAsync())
        {
            await holder.ExecuteAsync(new CommandDefinition("SELECT id FROM capacity_board.boards FOR UPDATE", transaction: transaction));
            async Task<string> Attempt(string name)
            {
                try { await repository.SaveAsync(new SaveRequest(Guid.NewGuid(), 5, [new WorkItem(Guid.NewGuid(), name, 10)])); return "saved"; }
                catch (BoardError error) { return error.Code; }
            }
            var first = Attempt("Independent one");
            var second = Attempt("Independent two");
            var blocked = false;
            for (var attempt = 0; attempt < 100; attempt++)
            {
                await using var observation = await observer.OpenConnectionAsync();
                await observation.ExecuteAsync("SELECT pg_stat_clear_snapshot()");
                if (await observation.ExecuteScalarAsync<int>("SELECT count(*)::int FROM pg_stat_activity WHERE application_name='capacity-board' AND cardinality(pg_blocking_pids(pid))>0") == 2)
                { blocked = true; break; }
                await Task.Delay(10);
            }
            Check(blocked && !first.IsCompleted && !second.IsCompleted, "two actual blocked sessions");
            var before = await repository.ReadAsync();
            Check(before.Revision == 5 && !first.IsCompleted && !second.IsCompleted, "independent coherent read before release");
            await transaction.CommitAsync();
            var results = await Task.WhenAll(first, second);
            Check(results.Count(x => x == "saved") == 1 && results.Count(x => x == "stale_revision") == 1, "one stale writer");
        }
        Check((await repository.ReadAsync()).Revision == 6, "one committed revision");
        Console.WriteLine("PASS actual independent parent-lock contention, read progress and stale rejection");

        await Reset();
        SaveRequest? final = null;
        BoardSnapshot? finalResult = null;
        for (var revision = 1; revision <= Allocation.MaxSaves; revision++)
        {
            final = new SaveRequest(Guid.NewGuid(), revision, [new WorkItem(Guid.NewGuid(), "Bounded save", revision % 10)]);
            finalResult = await repository.SaveAsync(final);
        }
        Check(finalResult!.Revision == 26 && await Scalar("SELECT count(*)::int FROM capacity_board.saves") == 25, "actual retained cap");
        Check(Describe(await repository.SaveAsync(final!)) == Describe(finalResult), "exact final save replay at cap");
        await Rejected(() => repository.SaveAsync(new SaveRequest(Guid.NewGuid(), 26, [])), "revision_limit");
        Console.WriteLine("PASS 25 actual retained saves, exact replay at cap and new-operation rejection");

        foreach (var sql in new[] {
            "CREATE TABLE capacity_board.forbidden(id int)", "CREATE TEMP TABLE forbidden(id int)",
            "CREATE SCHEMA forbidden", "SET ROLE capacity_migration", "DELETE FROM capacity_board.boards",
            "UPDATE capacity_board.boards SET capacity=29", "UPDATE capacity_board.work_items SET points=1",
            "UPDATE capacity_board.saves SET fingerprint=repeat('A',64)", "DELETE FROM capacity_board.saves",
            "SELECT * FROM capacity_board.schema_versions" })
            await SqlRejected(source, sql, "42501");
        await SqlRejected(source, "INSERT INTO capacity_board.work_items(board_id,id,position,name,points) VALUES ('11111111-1111-4111-8111-111111111111','55555555-5555-4555-8555-555555555555',20,'Invalid',1)", "23514");
        await SqlRejected(source, "INSERT INTO capacity_board.work_items(board_id,id,position,name,points) VALUES ('99999999-9999-4999-8999-999999999999','55555555-5555-4555-8555-555555555555',0,'Invalid',1)", "23503");
        await using (var conn = await source.OpenConnectionAsync())
        {
            await conn.ExecuteAsync("""
                INSERT INTO capacity_board.work_items(board_id,id,position,name,points) VALUES
                ('11111111-1111-4111-8111-111111111111','55555555-5555-4555-8555-555555555555',1,'Direct trusted SQL',30);
                """);
        }
        Check((await repository.ReadAsync()).Total > 30, "trusted role can bypass aggregate protocol");
        Console.WriteLine("PASS actual runtime grants/native constraints; direct SQL aggregate-capacity bypass disclosed");
        await Reset();

        async Task TrustFailure(string variable, string replacement, string description)
        {
            var original = Environment.GetEnvironmentVariable(variable);
            try
            {
                Environment.SetEnvironmentVariable(variable, replacement);
                await using var bad = Database.Create("capacity_app");
                try { await using var connection = await bad.OpenConnectionAsync(); }
                catch (NpgsqlException error)
                {
                    Check(error.ToString().Contains("AuthenticationException") &&
                        (error.ToString().Contains("certificate", StringComparison.OrdinalIgnoreCase) ||
                         error.ToString().Contains("RemoteCertificate", StringComparison.OrdinalIgnoreCase)), "certificate-specific failure");
                    Console.WriteLine($"PASS actual Npgsql {description} certificate failure");
                    return;
                }
                throw new Exception("TLS negative connected");
            }
            finally { Environment.SetEnvironmentVariable(variable, original); }
        }
        await TrustFailure("PGSSLROOTCERT", Environment.GetEnvironmentVariable("WRONG_CA")!, "wrong-CA");
        var addresses = await Dns.GetHostAddressesAsync(Environment.GetEnvironmentVariable("PGHOST")!);
        await TrustFailure("PGHOST", addresses.First(x => x.AddressFamily == AddressFamily.InterNetwork).ToString(), "wrong-host");
        await using (var positive = Database.Create("capacity_app"))
        await using (var conn = await positive.OpenConnectionAsync())
            Check(await conn.ExecuteScalarAsync<bool>("SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()"), "positive same-service TLS");
        Console.WriteLine("PASS same-service official-CA/DNS positive TLS control");
        Console.WriteLine("All seven Cloud groups passed; browser suite uses a freshly reseeded owner fixture.");
    }
}
