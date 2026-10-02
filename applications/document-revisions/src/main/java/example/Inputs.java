package example;

import jakarta.ws.rs.BadRequestException;
import java.util.UUID;

public final class Inputs {
    public static final long MAX_VERSION = 1_000_000_000L;
    private Inputs() {}

    public static UUID uuid(String value) {
        if (value == null || !value.matches("(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")) {
            throw new BadRequestException("A canonical UUID is required");
        }
        return UUID.fromString(value);
    }

    public static long version(Long value, long minimum) {
        if (value == null || value < minimum || value > MAX_VERSION) {
            throw new BadRequestException("Version is outside the supported range");
        }
        return value;
    }

    public static String text(String value, int maximum, boolean multiline) {
        if (value == null || value.isBlank() || value.length() > maximum) {
            throw new BadRequestException("Text is missing or too long");
        }
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            if (Character.isHighSurrogate(c)) {
                if (++i >= value.length() || !Character.isLowSurrogate(value.charAt(i))) {
                    throw new BadRequestException("Text contains invalid Unicode");
                }
            } else if (Character.isLowSurrogate(c)
                || (Character.isISOControl(c) && !(multiline && (c == '\n' || c == '\r' || c == '\t')))) {
                throw new BadRequestException("Text contains unsupported characters");
            }
        }
        return value;
    }
}
