package com.example.expenses;

public class Problem extends RuntimeException {
  final int status;

  public Problem(int status, String message) {
    super(message);
    this.status = status;
  }
}
