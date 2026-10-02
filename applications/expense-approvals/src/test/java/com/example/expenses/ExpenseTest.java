package com.example.expenses;

import static org.junit.jupiter.api.Assertions.*;

import java.math.BigDecimal;
import org.junit.jupiter.api.Test;

class ExpenseTest {
  @Test
  void fixedPrecisionAndTerminalState() {
    var e = new Expense("employee-a", "Notebook", new BigDecimal("12.34"), "GBP");
    assertEquals("12.34", e.view().amount());
    e.submit();
    e.decide(new Actor("manager-a", Actor.Role.MANAGER), true, null);
    assertEquals(Expense.Status.APPROVED, e.status());
    assertThrows(Problem.class, () -> e.submit());
  }

  @Test
  void rejectsInvalidMoney() {
    for (String n : new String[] {"-1", "0", "100000.01", "1.001"})
      assertThrows(Problem.class, () -> new Expense("a", "Paper", new BigDecimal(n), "GBP"));
  }

  @Test
  void cannotDecideOwnExpense() {
    var e = new Expense("manager-a", "Paper", BigDecimal.ONE, "GBP");
    e.submit();
    assertThrows(
        Problem.class, () -> e.decide(new Actor("manager-a", Actor.Role.MANAGER), true, null));
    assertEquals(Expense.Status.SUBMITTED, e.status());
  }

  @Test
  void rejectionRequiresReason() {
    var e = new Expense("employee-a", "Paper", BigDecimal.ONE, "GBP");
    e.submit();
    assertThrows(
        Problem.class, () -> e.decide(new Actor("manager-a", Actor.Role.MANAGER), false, " "));
    e.decide(new Actor("manager-a", Actor.Role.MANAGER), false, "Receipt missing");
    assertEquals(Expense.Status.REJECTED, e.status());
  }
}
