package com.example.expenses;

import jakarta.servlet.*;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
public class TokenFilter extends OncePerRequestFilter {
  private record Entry(byte[] digest, Actor actor) {}

  private final List<Entry> entries = new ArrayList<>();

  public TokenFilter() {
    Set<String> tokens = new HashSet<>();
    Map<String, Actor.Role> identities = new HashMap<>();
    for (String entry : SchemaMigrate.required("APP_TOKENS").split(",")) {
      String[] p = entry.split(":", -1);
      if (p.length != 3
          || !p[0].matches("[a-zA-Z0-9_-]{1,64}")
          || p[2].length() < 32
          || p[2].length() > 256
          || !tokens.add(p[2])) throw new IllegalArgumentException("Invalid APP_TOKENS");
      Actor.Role role = Actor.Role.valueOf(p[1]);
      Actor.Role previous = identities.putIfAbsent(p[0], role);
      if (previous != null && previous != role)
        throw new IllegalArgumentException("Identity has conflicting roles");
      entries.add(new Entry(hash(p[2]), new Actor(p[0], role)));
    }
  }

  private static byte[] hash(String s) {
    try {
      return MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8));
    } catch (Exception e) {
      throw new IllegalStateException(e);
    }
  }

  @Override
  protected void doFilterInternal(
      HttpServletRequest req, HttpServletResponse res, FilterChain chain)
      throws ServletException, IOException {
    if (req.getRequestURI().equals("/health") && req.getMethod().equals("GET")) {
      chain.doFilter(req, res);
      return;
    }
    String header = req.getHeader("Authorization");
    Actor actor = null;
    if (header != null && header.startsWith("Bearer ") && header.length() <= 263) {
      byte[] candidate = hash(header.substring(7));
      for (Entry e : entries) if (MessageDigest.isEqual(candidate, e.digest())) actor = e.actor();
    }
    if (actor == null) {
      res.setStatus(401);
      res.setHeader("WWW-Authenticate", "Bearer");
      res.setContentType("application/json");
      res.getWriter().write("{\"error\":\"authentication_required\"}");
      return;
    }
    req.setAttribute("actor", actor);
    chain.doFilter(req, res);
  }
}
