package com.example.expenses;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.util.*;
import org.springframework.web.bind.annotation.*;

@RestController
public class Api {
  public record Fields(
      @NotBlank @Size(max = 300) String description,
      @NotNull @DecimalMin("0.01") @DecimalMax("100000.00") @Digits(integer = 6, fraction = 2)
          BigDecimal amount,
      @NotNull @Pattern(regexp = "GBP") String currency) {}

  public record Edit(
      @NotBlank @Size(max = 300) String description,
      @NotNull @DecimalMin("0.01") @DecimalMax("100000.00") @Digits(integer = 6, fraction = 2)
          BigDecimal amount,
      @NotNull @Pattern(regexp = "GBP") String currency,
      @NotNull @PositiveOrZero Long version) {}

  public record Version(@NotNull @PositiveOrZero Long version) {}

  public record Decision(@NotNull @PositiveOrZero Long version, @Size(max = 500) String note) {}

  private final ExpenseService service;

  public Api(ExpenseService service) {
    this.service = service;
  }

  @GetMapping("/health")
  public Map<String, String> health() {
    return Map.of("status", "ok");
  }

  @PostMapping("/expenses")
  @ResponseStatus(org.springframework.http.HttpStatus.CREATED)
  public Expense.View create(@RequestAttribute Actor actor, @Valid @RequestBody Fields fields) {
    return service.create(actor, fields);
  }

  @GetMapping("/expenses")
  public List<Expense.View> list(
      @RequestAttribute Actor actor, @RequestParam(required = false) Expense.Status status) {
    return service.list(actor, status);
  }

  @GetMapping("/expenses/{id}")
  public Expense.View get(@RequestAttribute Actor actor, @PathVariable UUID id) {
    return service.get(actor, id);
  }

  @PutMapping("/expenses/{id}")
  public Expense.View edit(
      @RequestAttribute Actor actor, @PathVariable UUID id, @Valid @RequestBody Edit body) {
    return service.edit(actor, id, body);
  }

  @PostMapping("/expenses/{id}/submit")
  public Expense.View submit(
      @RequestAttribute Actor actor, @PathVariable UUID id, @Valid @RequestBody Version body) {
    return service.submit(actor, id, body.version());
  }

  @PostMapping("/expenses/{id}/approve")
  public Expense.View approve(
      @RequestAttribute Actor actor, @PathVariable UUID id, @Valid @RequestBody Decision body) {
    return service.decide(actor, id, body, true);
  }

  @PostMapping("/expenses/{id}/reject")
  public Expense.View reject(
      @RequestAttribute Actor actor, @PathVariable UUID id, @Valid @RequestBody Decision body) {
    return service.decide(actor, id, body, false);
  }
}
