package example;

import org.flywaydb.core.Flyway;
import org.postgresql.ds.PGSimpleDataSource;

/** Setup-only command: does not start Quarkus or the HTTP application. */
public final class Migrate {
    public static void main(String[] args) {
        PGSimpleDataSource source = new PGSimpleDataSource();
        source.setURL(JdbcUrl.validate(required("JDBC_URL")));
        source.setUser("revision_migrator");
        source.setPassword(required("MIGRATOR_PASSWORD"));
        source.setSslMode("verify-full");
        source.setSslRootCert(required("PGSSLROOTCERT"));
        source.setConnectTimeout(5);
        source.setSocketTimeout(15);
        var result = Flyway.configure().dataSource(source)
            .schemas("revision_api").defaultSchema("revision_api")
            .locations("classpath:db/migration").initSql("SET ROLE revision_owner")
            .cleanDisabled(true).load().migrate();
        System.out.println("Flyway migrations executed: " + result.migrationsExecuted);
    }
    private static String required(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) throw new IllegalArgumentException("Missing " + name);
        return value;
    }
}
