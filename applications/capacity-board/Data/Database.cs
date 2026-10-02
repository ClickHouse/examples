using Npgsql;

namespace CapacityBoard.Data;

public static class Database
{
    public static NpgsqlDataSource Create(string expectedRole)
    {
        string Required(string name) => Environment.GetEnvironmentVariable(name)
            ?? throw new InvalidOperationException($"Missing {name}");
        if (Required("PGUSER") != expectedRole)
            throw new InvalidOperationException("Wrong database role");
        var connection = new NpgsqlConnectionStringBuilder
        {
            Host = Required("PGHOST"),
            Port = int.Parse(Required("PGPORT")),
            Database = Required("PGDATABASE"),
            Username = Required("PGUSER"),
            Password = Required("PGPASSWORD"),
            RootCertificate = Required("PGSSLROOTCERT"),
            SslMode = SslMode.VerifyFull,
            Timeout = 5,
            CommandTimeout = 4,
            MaxPoolSize = 4,
            MinPoolSize = 0,
            ConnectionIdleLifetime = 60,
            ConnectionLifetime = 300,
            ApplicationName = "capacity-board",
            Options = "-c statement_timeout=4000 -c lock_timeout=2000 -c idle_in_transaction_session_timeout=6000"
        };
        return NpgsqlDataSource.Create(connection.ConnectionString);
    }
}
