package example;

import jakarta.annotation.security.PermitAll;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

@Path("/live")
@PermitAll
public class LiveResource {
    @GET public String live() { return "up"; }
}
