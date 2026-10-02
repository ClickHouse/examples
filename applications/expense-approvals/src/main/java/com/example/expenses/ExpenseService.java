package com.example.expenses;

import java.util.*;
import org.springframework.data.domain.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional
public class ExpenseService {
  private final ExpenseRepository repository;

  public ExpenseService(ExpenseRepository repository) {
    this.repository = repository;
  }

  public Expense.View create(Actor actor, Api.Fields fields) {
    return repository
        .saveAndFlush(
            new Expense(actor.id(), fields.description(), fields.amount(), fields.currency()))
        .view();
  }

  private Expense visible(Actor actor, UUID id) {
    Expense e = repository.findById(id).orElseThrow(() -> new Problem(404, "expense_not_found"));
    if (!e.owner().equals(actor.id()) && !(actor.manager() && e.status() != Expense.Status.DRAFT))
      throw new Problem(404, "expense_not_found");
    return e;
  }

  private Expense owned(Actor actor, UUID id, long version) {
    Expense e = visible(actor, id);
    if (!e.owner().equals(actor.id())) throw new Problem(403, "owner_required");
    checkVersion(e, version);
    return e;
  }

  private void checkVersion(Expense e, long version) {
    if (e.version() != version) throw new Problem(409, "stale_version");
  }

  @Transactional(readOnly = true)
  public Expense.View get(Actor actor, UUID id) {
    return visible(actor, id).view();
  }

  @Transactional(readOnly = true)
  public List<Expense.View> list(Actor actor, Expense.Status status) {
    return repository
        .findAll(
            (root, q, cb) -> {
              var own = cb.equal(root.get("ownerId"), actor.id());
              var visibility =
                  actor.manager()
                      ? cb.or(own, cb.notEqual(root.get("status"), Expense.Status.DRAFT))
                      : own;
              return status == null
                  ? visibility
                  : cb.and(visibility, cb.equal(root.get("status"), status));
            },
            PageRequest.of(0, 100, Sort.by(Sort.Direction.DESC, "createdAt", "id")))
        .stream()
        .map(Expense::view)
        .toList();
  }

  public Expense.View edit(Actor actor, UUID id, Api.Edit body) {
    Expense e = owned(actor, id, body.version());
    e.edit(body.description(), body.amount(), body.currency());
    repository.flush();
    return e.view();
  }

  public Expense.View submit(Actor actor, UUID id, long version) {
    Expense e = owned(actor, id, version);
    e.submit();
    repository.flush();
    return e.view();
  }

  public Expense.View decide(Actor actor, UUID id, Api.Decision body, boolean approve) {
    if (!actor.manager()) throw new Problem(403, "manager_required");
    Expense e = visible(actor, id);
    checkVersion(e, body.version());
    e.decide(actor, approve, body.note());
    repository.flush();
    return e.view();
  }
}
