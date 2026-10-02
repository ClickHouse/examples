using Microsoft.EntityFrameworkCore;
using Npgsql;
namespace HabitApi;

public sealed record HabitView(Guid Id, string Name, bool Archived, DateTime CreatedAt);
public sealed record CheckInView(Guid Id, DateOnly CompletedOn, DateTime CreatedAt);

public sealed class HabitService(HabitDb db)
{
    public async Task<HabitView> Create(string owner, string? name)
    {
        if (string.IsNullOrWhiteSpace(name) || name.Length > 100 || name.Contains('\0')) throw new ApiProblem(400, "invalid_habit_name");
        var habit = new Habit { OwnerId = owner, Name = name.Trim() };
        db.Habits.Add(habit);
        await db.SaveChangesAsync();
        return View(habit);
    }

    public Task<List<HabitView>> List(string owner) => db.Habits.AsNoTracking()
        .Where(h => h.OwnerId == owner).OrderByDescending(h => h.CreatedAt).ThenByDescending(h => h.Id)
        .Take(100).Select(h => new HabitView(h.Id, h.Name, h.Archived, h.CreatedAt)).ToListAsync();

    private async Task<Habit> LockedOwned(string owner, Guid id)
    {
        // All archive/check-in/undo paths lock this row before inspecting state.
        var rows = await db.Habits.FromSqlInterpolated($"SELECT * FROM habits.habit WHERE id={id} AND owner_id={owner} FOR UPDATE").ToListAsync();
        return rows.SingleOrDefault() ?? throw new ApiProblem(404, "habit_not_found");
    }

    public async Task<CheckInView> Complete(string owner, Guid id, DateOnly date)
    {
        await using var tx = await db.Database.BeginTransactionAsync();
        var habit = await LockedOwned(owner, id);
        var existing = await db.CheckIns.SingleOrDefaultAsync(c => c.HabitId == id && c.CompletedOn == date);
        if (existing is not null)
        {
            await tx.CommitAsync();
            return View(existing);
        }
        if (habit.Archived) throw new ApiProblem(409, "habit_archived");
        var checkIn = new CheckIn { HabitId = id, CompletedOn = date };
        db.CheckIns.Add(checkIn);
        try
        {
            await db.SaveChangesAsync();
        }
        catch (DbUpdateException e) when (e.InnerException is PostgresException
        { SqlState: PostgresErrorCodes.UniqueViolation, ConstraintName: "uq_check_in_habit_date" })
        {
            // Discard the attempted write and tracking before reading the durable winner.
            await tx.RollbackAsync();
            db.ChangeTracker.Clear();
            var winner = await db.CheckIns.AsNoTracking().SingleAsync(c => c.HabitId == id && c.CompletedOn == date);
            return View(winner);
        }
        await tx.CommitAsync();
        return View(checkIn);
    }

    public async Task Undo(string owner, Guid id, DateOnly date)
    {
        await using var tx = await db.Database.BeginTransactionAsync();
        await LockedOwned(owner, id);
        // Undo is permitted even after archive.
        var checkIn = await db.CheckIns.SingleOrDefaultAsync(c => c.HabitId == id && c.CompletedOn == date);
        if (checkIn is not null)
        {
            db.CheckIns.Remove(checkIn);
            await db.SaveChangesAsync();
        }
        await tx.CommitAsync();
    }

    public async Task<HabitView> Archive(string owner, Guid id)
    {
        await using var tx = await db.Database.BeginTransactionAsync();
        var habit = await LockedOwned(owner, id);
        habit.Archived = true;
        await db.SaveChangesAsync();
        await tx.CommitAsync();
        return View(habit);
    }

    public async Task<List<CheckInView>> History(string owner, Guid id, string month)
    {
        var (start, end) = CalendarContract.Month(month);
        if (!await db.Habits.AnyAsync(h => h.Id == id && h.OwnerId == owner)) throw new ApiProblem(404, "habit_not_found");
        return await db.CheckIns.AsNoTracking().Where(c => c.HabitId == id && c.CompletedOn >= start && c.CompletedOn < end)
            .OrderBy(c => c.CompletedOn).Take(31).Select(c => new CheckInView(c.Id, c.CompletedOn, c.CreatedAt)).ToListAsync();
    }

    private static HabitView View(Habit h) => new(h.Id, h.Name, h.Archived, h.CreatedAt);
    private static CheckInView View(CheckIn c) => new(c.Id, c.CompletedOn, c.CreatedAt);
}
