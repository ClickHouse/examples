package com.example.expenses;

import static org.junit.jupiter.api.Assertions.*;

import java.math.BigDecimal;
import java.sql.*;
import java.util.*;
import java.util.concurrent.*;
import javax.sql.DataSource;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
class CloudIT {
  @Autowired ExpenseRepository repository;
  @Autowired PlatformTransactionManager manager;
  @Autowired DataSource source;

  @Test
  void nativeVersionRace() throws Exception {
    UUID id =
        repository
            .saveAndFlush(new Expense("employee-a", "Native race", new BigDecimal("2.34"), "GBP"))
            .id();
    var barrier = new CyclicBarrier(2);
    var executor = Executors.newFixedThreadPool(2);
    Callable<Boolean> contender =
        () -> {
          try {
            new TransactionTemplate(manager)
                .executeWithoutResult(
                    tx -> {
                      var e = repository.findById(id).orElseThrow();
                      try {
                        barrier.await(20, TimeUnit.SECONDS);
                      } catch (Exception x) {
                        throw new RuntimeException(x);
                      }
                      e.submit();
                      repository.flush();
                    });
            return true;
          } catch (org.springframework.dao.OptimisticLockingFailureException e) {
            return false;
          }
        };
    try {
      var a = executor.submit(contender);
      var b = executor.submit(contender);
      assertNotEquals(a.get(60, TimeUnit.SECONDS), b.get(60, TimeUnit.SECONDS));
      assertEquals(1, repository.findById(id).orElseThrow().version());
    } finally {
      executor.shutdownNow();
      repository.deleteById(id);
    }
  }

  @Test
  void rollbackAfterFlush() {
    UUID[] id = {null};
    assertThrows(
        IllegalStateException.class,
        () ->
            new TransactionTemplate(manager)
                .executeWithoutResult(
                    tx -> {
                      var e =
                          repository.saveAndFlush(
                              new Expense("employee-a", "Rollback", BigDecimal.ONE, "GBP"));
                      id[0] = e.id();
                      throw new IllegalStateException("forced rollback");
                    }));
    assertFalse(repository.existsById(id[0]));
  }

  @Test
  void runtimeCannotCreateOrReadMigrationHistory() throws Exception {
    try (var c = source.getConnection()) {
      for (String sql :
          List.of(
              "CREATE TABLE expenses.forbidden (id int)",
              "SELECT * FROM expenses.flyway_schema_history")) {
        var e = assertThrows(SQLException.class, () -> c.createStatement().execute(sql));
        assertEquals("42501", e.getSQLState());
      }
      try (var r =
          c.createStatement()
              .executeQuery("SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()")) {
        assertTrue(r.next());
        assertTrue(r.getBoolean(1));
      }
    }
  }

  @Test
  void databaseRejectsMalformedDecisions() throws Exception {
    UUID id =
        repository
            .saveAndFlush(new Expense("employee-a", "Constraints", BigDecimal.ONE, "GBP"))
            .id();
    try (var c = source.getConnection()) {
      for (String update :
          List.of(
              "status='REJECTED', submitted_at=now(), decided_at=now(), decided_by='manager-a',"
                  + " decision_note=NULL",
              "decided_by='manager-a'",
              "decided_at=now()")) {
        try (var stmt =
            c.prepareStatement("UPDATE expenses.expense SET " + update + " WHERE id=?")) {
          stmt.setObject(1, id);
          var e = assertThrows(SQLException.class, stmt::executeUpdate);
          assertEquals("23514", e.getSQLState());
        }
      }
    } finally {
      repository.deleteById(id);
    }
  }

  @Test
  void wrongCaFails() throws Exception {
    Properties p = new Properties();
    p.setProperty("user", System.getenv("PGUSER"));
    p.setProperty("password", System.getenv("PGPASSWORD"));
    p.setProperty("sslmode", "verify-full");
    p.setProperty("sslrootcert", "/etc/ssl/certs/ca-certificates.crt");
    // Positive control uses the same endpoint, role and password with the configured Cloud CA.
    try (var connection = source.getConnection()) {
      assertTrue(connection.isValid(10));
    }
    SQLException error =
        assertThrows(
            SQLException.class,
            () ->
                DriverManager.getConnection(
                    "jdbc:postgresql://" + System.getenv("PGHOST") + ":5432/postgres", p));
    StringBuilder causes = new StringBuilder();
    for (Throwable cause = error; cause != null; cause = cause.getCause()) {
      causes.append(cause.getMessage()).append(" ");
    }
    String message = causes.toString().toLowerCase(java.util.Locale.ROOT);
    assertTrue(
        message.contains("pkix")
            || message.contains("certification path")
            || message.contains("trustanchors"),
        "Expected certificate trust-path failure");
  }
}
