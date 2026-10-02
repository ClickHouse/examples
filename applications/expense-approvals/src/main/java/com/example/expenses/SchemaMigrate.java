package com.example.expenses;

import org.flywaydb.core.Flyway;
import org.postgresql.ds.PGSimpleDataSource;

/** Explicit DDL command. Never started by the API. */
public class SchemaMigrate {
  public static void main(String[] args) {
    var ds = new PGSimpleDataSource();
    ds.setServerNames(new String[] {required("PGHOST")});
    ds.setPortNumbers(new int[] {Integer.parseInt(System.getenv().getOrDefault("PGPORT", "5432"))});
    ds.setDatabaseName(System.getenv().getOrDefault("PGDATABASE", "postgres"));
    ds.setUser(required("PGUSER"));
    ds.setPassword(required("PGPASSWORD"));
    ds.setSslMode("verify-full");
    ds.setSslRootCert(required("PGSSLROOTCERT"));
    Flyway.configure()
        .dataSource(ds)
        .schemas("expenses")
        .defaultSchema("expenses")
        .createSchemas(false)
        .locations("classpath:db/migration")
        .load()
        .migrate();
  }

  static String required(String k) {
    String v = System.getenv(k);
    if (v == null || v.isBlank()) throw new IllegalArgumentException("Missing " + k);
    return v;
  }
}
