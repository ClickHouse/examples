using Npgsql;
namespace HabitApi;

public static class PgConfig
{
    public static string Required(string name) => Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
        ? value : throw new InvalidOperationException($"Missing {name}");

    public static string ConnectionString() => new NpgsqlConnectionStringBuilder
    {
        Host = Required("PGHOST"),
        Port = int.Parse(Environment.GetEnvironmentVariable("PGPORT") ?? "5432"),
        Database = Environment.GetEnvironmentVariable("PGDATABASE") ?? "postgres",
        Username = Required("PGUSER"),
        Password = Required("PGPASSWORD"),
        SslMode = SslMode.VerifyFull,
        RootCertificate = Required("PGSSLROOTCERT"),
        SearchPath = "habits",
        MaxPoolSize = 5,
        Timeout = 15,
        CommandTimeout = 30,
        GssEncryptionMode = GssEncryptionMode.Disable
    }.ConnectionString;
}
