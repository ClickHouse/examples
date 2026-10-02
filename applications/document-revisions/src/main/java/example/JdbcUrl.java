package example;

import java.net.URI;

/** Reject URL properties, which pgJDBC would prefer over separately configured TLS properties. */
public final class JdbcUrl {
    private JdbcUrl() {}
    public static String validate(String value) {
        if (value == null || !value.startsWith("jdbc:postgresql://")) invalid();
        URI uri;
        try { uri = URI.create(value.substring(5)); }
        catch (IllegalArgumentException error) { throw new IllegalArgumentException("Invalid JDBC endpoint"); }
        if (uri.getHost() == null || uri.getPort() < 1 || uri.getPort() > 65535
            || uri.getUserInfo() != null || uri.getRawQuery() != null || uri.getRawFragment() != null
            || uri.getRawPath() == null || !uri.getRawPath().matches("/[A-Za-z0-9_%.-]+")) invalid();
        return value;
    }
    private static void invalid() { throw new IllegalArgumentException("Use a simple JDBC host:port/database URL without properties"); }
}
