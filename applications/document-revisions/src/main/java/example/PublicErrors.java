package example;

import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;
import org.jboss.logging.Logger;

@Provider
public class PublicErrors implements ExceptionMapper<Exception> {
    private static final Logger LOG = Logger.getLogger(PublicErrors.class);
    @Override public Response toResponse(Exception error) {
        if (error instanceof WebApplicationException web) {
            int status = web.getResponse().getStatus();
            String message = switch (status) {
                case 400 -> "Invalid request";
                case 401 -> "Authentication required";
                case 404 -> "Document or revision not found";
                case 409 -> "Version changed; refetch before retrying";
                default -> "Request rejected";
            };
            return Response.status(status).entity(new Dtos.Error(message)).build();
        }
        // Infrastructure detail stays in operator logs, never in response DTOs.
        LOG.error("Document transaction failed", error);
        return Response.status(503).entity(new Dtos.Error("Database temporarily unavailable")).build();
    }
}
