package com.example.expenses;

public record Actor(String id, Role role) {
  public enum Role {
    EMPLOYEE,
    MANAGER
  }

  public boolean manager() {
    return role == Role.MANAGER;
  }
}
