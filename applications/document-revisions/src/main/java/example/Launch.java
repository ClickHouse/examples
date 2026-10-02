package example;

import io.quarkus.runtime.Quarkus;
import io.quarkus.runtime.annotations.QuarkusMain;

@QuarkusMain
public class Launch {
    public static void main(String[] args) {
        JdbcUrl.validate(System.getenv("JDBC_URL")); // Before Quarkus creates any database pool.
        Quarkus.run(args);
    }
}
