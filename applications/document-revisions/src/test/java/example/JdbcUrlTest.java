package example;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class JdbcUrlTest {
    @Test void urlCannotOverrideTlsProperties() {
        assertEquals("jdbc:postgresql://db.example:5432/postgres", JdbcUrl.validate("jdbc:postgresql://db.example:5432/postgres"));
        for (String url : new String[] {"jdbc:postgresql://db.example:5432/postgres?sslmode=disable",
            "jdbc:postgresql://user@db.example:5432/postgres", "jdbc:postgresql://db.example:5432/postgres#x",
            "jdbc:postgresql://db.example/postgres", "jdbc:postgresql://db.example:99999/postgres"}) {
            assertThrows(IllegalArgumentException.class, () -> JdbcUrl.validate(url));
        }
    }
}
