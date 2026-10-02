package example;

import jakarta.ws.rs.BadRequestException;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class InputsTest {
    @Test void nullAndCanonicalUuidBoundaries() {
        assertThrows(BadRequestException.class, () -> Inputs.uuid(null));
        assertThrows(BadRequestException.class, () -> Inputs.uuid("1-1-1-1-1"));
        assertEquals("abcdef00-0000-0000-0000-000000000001",
            Inputs.uuid("ABCDEF00-0000-0000-0000-000000000001").toString());
        assertThrows(BadRequestException.class, () -> Inputs.version(null, 0));
        assertThrows(BadRequestException.class, () -> Inputs.version(-1L, 0));
        assertThrows(BadRequestException.class, () -> Inputs.version(1_000_000_001L, 0));
        assertEquals(0, Inputs.version(0L, 0));
    }
    @Test void textRejectsDatabaseAndEncodingFailures() {
        assertThrows(BadRequestException.class, () -> Inputs.text(null, 120, false));
        assertThrows(BadRequestException.class, () -> Inputs.text(" ", 120, false));
        assertThrows(BadRequestException.class, () -> Inputs.text("x".repeat(121), 120, false));
        assertThrows(BadRequestException.class, () -> Inputs.text("x\u0000", 120, true));
        assertThrows(BadRequestException.class, () -> Inputs.text("x\ud800", 120, true));
        assertThrows(BadRequestException.class, () -> Inputs.text("\udc00", 120, true));
        assertThrows(BadRequestException.class, () -> Inputs.text("title\n", 120, false));
        assertEquals("body\n\t😀", Inputs.text("body\n\t😀", 16_000, true));
    }
}
