using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
namespace HabitApi;

public sealed class Habit
{
    public Guid Id
    {
        get;
        set;
    } = Guid.NewGuid();
    public required string OwnerId
    {
        get;
        set;
    }
    public required string Name
    {
        get;
        set;
    }
    public bool Archived
    {
        get;
        set;
    }
    public DateTime CreatedAt
    {
        get;
        set;
    } = DateTime.UtcNow;
    public List<CheckIn> CheckIns
    {
        get;
        set;
    } = [];
}

public sealed class CheckIn
{
    public Guid Id
    {
        get;
        set;
    } = Guid.NewGuid();
    public Guid HabitId
    {
        get;
        set;
    }
    public Habit Habit
    {
        get;
        set;
    } = null!;
    public DateOnly CompletedOn
    {
        get;
        set;
    }
    public DateTime CreatedAt
    {
        get;
        set;
    } = DateTime.UtcNow;
}

public sealed class HabitDb(DbContextOptions<HabitDb> options) : DbContext(options)
{
    public DbSet<Habit> Habits => Set<Habit>();
    public DbSet<CheckIn> CheckIns => Set<CheckIn>();
    protected override void OnModelCreating(ModelBuilder model)
    {
        model.HasDefaultSchema("habits");
        model.Entity<Habit>(e =>
        {
            e.ToTable("habit", t => t.HasCheckConstraint("habit_name_nonblank", "length(btrim(name)) > 0"));
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
            e.Property(x => x.OwnerId).HasColumnName("owner_id").HasMaxLength(64).IsRequired();
            e.Property(x => x.Name).HasColumnName("name").HasMaxLength(100).IsRequired();
            e.Property(x => x.Archived).HasColumnName("archived");
            e.Property(x => x.CreatedAt).HasColumnName("created_at");
            e.HasIndex(x => new { x.OwnerId, x.CreatedAt, x.Id }).HasDatabaseName("habit_owner_created");
        });
        model.Entity<CheckIn>(e =>
        {
            e.ToTable("check_in", t => t.HasCheckConstraint("check_in_date_bound", "completed_on BETWEEN DATE '2000-01-01' AND DATE '2100-12-31'"));
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasColumnName("id").ValueGeneratedNever();
            e.Property(x => x.HabitId).HasColumnName("habit_id");
            e.Property(x => x.CompletedOn).HasColumnName("completed_on").HasColumnType("date");
            e.Property(x => x.CreatedAt).HasColumnName("created_at");
            e.HasOne(x => x.Habit).WithMany(x => x.CheckIns).HasForeignKey(x => x.HabitId).OnDelete(DeleteBehavior.Cascade);
            e.HasIndex(x => new { x.HabitId, x.CompletedOn }).IsUnique().HasDatabaseName("uq_check_in_habit_date");
        });
    }
}

// dotnet-ef uses this explicit design-time path and the credential supplied to its process.
public sealed class MigrationFactory : IDesignTimeDbContextFactory<HabitDb>
{
    public HabitDb CreateDbContext(string[] args) => new(new DbContextOptionsBuilder<HabitDb>()
        .UseNpgsql(PgConfig.ConnectionString(), pg => pg.MigrationsHistoryTable("__EFMigrationsHistory", "habits")).Options);
}
