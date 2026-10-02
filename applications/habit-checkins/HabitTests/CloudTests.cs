using System.Security.Authentication;
using HabitApi;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Npgsql;
using Xunit;

namespace HabitTests;

[Trait("Category", "Cloud")]
public sealed class CloudTests
{
    private static HabitDb Db(string? applicationName = null)
    {
        var connection = new NpgsqlConnectionStringBuilder(PgConfig.ConnectionString());
        if (applicationName is not null) connection.ApplicationName = applicationName;
        return new HabitDb(new DbContextOptionsBuilder<HabitDb>().UseNpgsql(connection.ConnectionString).Options);
    }

    private static async Task<Guid> Create()
    {
        await using var db = Db();
        return (await new HabitService(db).Create("user-a", "Cloud fixture")).Id;
    }
    private static async Task Remove(Guid id)
    {
        await using var db = Db();
        await db.Habits.Where(h => h.Id == id).ExecuteDeleteAsync();
    }

    [Fact]
    public async Task NaturalKeyRejectsDuplicateDatabaseWriters()
    {
        var id = await Create();
        async Task<bool> Insert()
        {
            await using var db = Db();
            db.CheckIns.Add(new CheckIn { HabitId = id, CompletedOn = new DateOnly(2026, 10, 5) });
            try
            {
                await db.SaveChangesAsync();
                return true;
            }
            catch (DbUpdateException error)
            {
                var pg = Assert.IsType<PostgresException>(error.InnerException);
                Assert.Equal(PostgresErrorCodes.UniqueViolation, pg.SqlState);
                Assert.Equal("uq_check_in_habit_date", pg.ConstraintName);
                return false;
            }
        }
        try
        {
            var results = await Task.WhenAll(Insert(), Insert());
            Assert.Single(results, success => success);
            await using var db = Db();
            Assert.Equal(1, await db.CheckIns.CountAsync(c => c.HabitId == id));
        }
        finally
        {
            await Remove(id);
        }
    }

    private static async Task WaitForRowLock(HabitDb keeper)
    {
        await using var command = new NpgsqlCommand(
            "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE pg_backend_pid() = ANY(pg_blocking_pids(pid)))",
            (NpgsqlConnection)keeper.Database.GetDbConnection(),
            (NpgsqlTransaction)keeper.Database.CurrentTransaction!.GetDbTransaction());

        for (var attempt = 0; attempt < 100; attempt++)
        {
            // Statistics views retain a snapshot within a transaction; refresh before observing the contender.
            await using var refresh = new NpgsqlCommand("SELECT pg_stat_clear_snapshot()",
                (NpgsqlConnection)keeper.Database.GetDbConnection(),
                (NpgsqlTransaction)keeper.Database.CurrentTransaction!.GetDbTransaction());
            await refresh.ExecuteNonQueryAsync();
            if ((bool)(await command.ExecuteScalarAsync())!) return;
            await Task.Delay(100);
        }
        Assert.Fail("Contending service did not reach the parent row lock");
    }

    [Fact]
    public async Task ArchiveCommitsBeforeBlockedCheckInRejectsNewCompletion()
    {
        var id = await Create();
        try
        {
            await using var keeper = Db();
            await using var tx = await keeper.Database.BeginTransactionAsync();
            var rows = await keeper.Habits.FromSqlInterpolated($"SELECT * FROM habits.habit WHERE id={id} FOR UPDATE").ToListAsync();
            var contender = Task.Run(async () =>
            {
                await using var db = Db("habit-check-contender");
                return await Assert.ThrowsAsync<ApiProblem>(() => new HabitService(db).Complete("user-a", id, new DateOnly(2026, 10, 5)));
            });
            await WaitForRowLock(keeper);
            rows.Single().Archived = true;
            await keeper.SaveChangesAsync();
            await tx.CommitAsync();
            Assert.Equal(409, (await contender.WaitAsync(TimeSpan.FromSeconds(30))).Status);
            Assert.Equal(0, await keeper.CheckIns.CountAsync(c => c.HabitId == id));
        }
        finally
        {
            await Remove(id);
        }
    }

    [Fact]
    public async Task CheckInCommitsBeforeBlockedArchiveRetainsCompletion()
    {
        var id = await Create();
        try
        {
            await using var keeper = Db();
            await using var tx = await keeper.Database.BeginTransactionAsync();
            await keeper.Habits.FromSqlInterpolated($"SELECT * FROM habits.habit WHERE id={id} FOR UPDATE").ToListAsync();
            keeper.CheckIns.Add(new CheckIn { HabitId = id, CompletedOn = new DateOnly(2026, 10, 5) });
            await keeper.SaveChangesAsync();
            var contender = Task.Run(async () =>
            {
                await using var db = Db("habit-archive-contender");
                return await new HabitService(db).Archive("user-a", id);
            });
            await WaitForRowLock(keeper);
            await tx.CommitAsync();
            Assert.True((await contender.WaitAsync(TimeSpan.FromSeconds(30))).Archived);
            Assert.Equal(1, await keeper.CheckIns.CountAsync(c => c.HabitId == id));
        }
        finally
        {
            await Remove(id);
        }
    }

    [Fact]
    public async Task RollbackAfterFlushLeavesNoHabit()
    {
        var id = Guid.NewGuid();
        await using var db = Db();
        await using (var tx = await db.Database.BeginTransactionAsync())
        {
            db.Habits.Add(new Habit { Id = id, OwnerId = "user-a", Name = "Rollback" });
            await db.SaveChangesAsync();
            await tx.RollbackAsync();
        }
        db.ChangeTracker.Clear();
        Assert.False(await db.Habits.AnyAsync(h => h.Id == id));
    }

    [Fact]
    public async Task RuntimeCannotCreateTablesOrReadMigrationHistory()
    {
        await using var connection = new NpgsqlConnection(PgConfig.ConnectionString());
        await connection.OpenAsync();
        foreach (var sql in new[] { "CREATE TABLE habits.forbidden (id int)", "SELECT * FROM habits.\"__EFMigrationsHistory\"" })
        {
            await using var command = new NpgsqlCommand(sql, connection);
            var error = await Assert.ThrowsAsync<PostgresException>(async () => await command.ExecuteNonQueryAsync());
            Assert.Equal(PostgresErrorCodes.InsufficientPrivilege, error.SqlState);
        }
        await using var encrypted = new NpgsqlCommand("SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()", connection);
        Assert.True((bool)(await encrypted.ExecuteScalarAsync())!);
    }

    [Fact]
    public async Task WrongCaFailsCertificateTrustWithPositiveControl()
    {
        await using var positive = new NpgsqlConnection(PgConfig.ConnectionString());
        await positive.OpenAsync();
        var wrong = new NpgsqlConnectionStringBuilder(PgConfig.ConnectionString())
        { RootCertificate = "/etc/ssl/certs/ca-certificates.crt", Pooling = false };
        await using var negative = new NpgsqlConnection(wrong.ConnectionString);
        var error = await Assert.ThrowsAsync<NpgsqlException>(() => negative.OpenAsync());
        Assert.IsType<AuthenticationException>(error.InnerException);
        Assert.Contains("certificate", error.ToString(), StringComparison.OrdinalIgnoreCase);
    }
}
