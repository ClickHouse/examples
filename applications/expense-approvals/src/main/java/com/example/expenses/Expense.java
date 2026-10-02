package com.example.expenses;

import jakarta.persistence.*;
import java.math.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "expense", schema = "expenses")
public class Expense {
  public enum Status {
    DRAFT,
    SUBMITTED,
    APPROVED,
    REJECTED
  }

  @Id private UUID id;

  @Column(nullable = false, updatable = false, length = 64)
  private String ownerId;

  @Column(nullable = false, length = 300)
  private String description;

  @Column(nullable = false, precision = 8, scale = 2)
  private BigDecimal amount;

  @Column(nullable = false, length = 3)
  private String currency;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false, length = 16)
  private Status status;

  @Version private Long version;

  @Column(nullable = false, updatable = false)
  private Instant createdAt;

  @Column(nullable = false)
  private Instant updatedAt;

  private Instant submittedAt, decidedAt;

  @Column(length = 64)
  private String decidedBy;

  @Column(length = 500)
  private String decisionNote;

  protected Expense() {}

  public Expense(String owner, String description, BigDecimal amount, String currency) {
    id = UUID.randomUUID();
    ownerId = owner;
    status = Status.DRAFT;
    createdAt = Instant.now();
    edit(description, amount, currency);
  }

  public void edit(String description, BigDecimal amount, String currency) {
    if (status != Status.DRAFT) throw new Problem(409, "only_drafts_can_be_edited");
    if (description == null
        || description.isBlank()
        || description.length() > 300
        || amount == null
        || amount.signum() <= 0
        || amount.compareTo(new BigDecimal("100000.00")) > 0
        || !"GBP".equals(currency)) throw new Problem(400, "invalid_expense");
    try {
      this.amount = amount.setScale(2, RoundingMode.UNNECESSARY);
    } catch (ArithmeticException e) {
      throw new Problem(400, "amount_requires_at_most_two_decimal_places");
    }
    this.description = description.trim();
    this.currency = currency;
    updatedAt = Instant.now();
  }

  public void submit() {
    if (status != Status.DRAFT) throw new Problem(409, "only_drafts_can_be_submitted");
    status = Status.SUBMITTED;
    submittedAt = updatedAt = Instant.now();
  }

  public void decide(Actor actor, boolean approve, String note) {
    if (!actor.manager() || actor.id().equals(ownerId))
      throw new Problem(403, "decision_not_allowed");
    if (status != Status.SUBMITTED)
      throw new Problem(409, "only_submitted_expenses_can_be_decided");
    if (note != null && note.length() > 500 || !approve && (note == null || note.isBlank()))
      throw new Problem(400, "rejection_requires_a_note");
    status = approve ? Status.APPROVED : Status.REJECTED;
    decidedBy = actor.id();
    decisionNote = note == null ? null : note.trim();
    decidedAt = updatedAt = Instant.now();
  }

  public UUID id() {
    return id;
  }

  public String owner() {
    return ownerId;
  }

  public Status status() {
    return status;
  }

  public long version() {
    return version == null ? 0 : version;
  }

  public View view() {
    return new View(
        id,
        ownerId,
        description,
        amount.toPlainString(),
        currency,
        status,
        version(),
        createdAt,
        updatedAt,
        submittedAt,
        decidedAt,
        decidedBy,
        decisionNote);
  }

  public record View(
      UUID id,
      String ownerId,
      String description,
      String amount,
      String currency,
      Status status,
      long version,
      Instant createdAt,
      Instant updatedAt,
      Instant submittedAt,
      Instant decidedAt,
      String decidedBy,
      String decisionNote) {}
}
