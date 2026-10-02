package example;

import io.quarkus.security.Authenticated;
import io.quarkus.security.identity.SecurityIdentity;
import jakarta.inject.Inject;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.*;
import java.util.List;
import java.util.UUID;

@Path("/documents")
@Authenticated
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class DocumentsResource {
    @Inject Workflow workflow;
    @Inject SecurityIdentity identity;
    private UUID account() { return UUID.fromString(identity.getPrincipal().getName()); }

    @POST public Response create(Dtos.Create input) {
        var saved = workflow.create(account(), input); // CDI proxy commits before this returns.
        return Response.status(201).entity(saved).build();
    }
    @GET public List<Dtos.Summary> list() { return workflow.list(account()); }
    @POST @Path("/{id}/revisions") public Dtos.Summary edit(@PathParam("id") String id, Dtos.Edit input) {
        return workflow.edit(account(), Inputs.uuid(id), input);
    }
    @POST @Path("/{id}/publication") public Dtos.Summary publish(@PathParam("id") String id, Dtos.Publish input) {
        return workflow.publish(account(), Inputs.uuid(id), input);
    }
    @GET @Path("/{id}/draft") public Dtos.Content draft(@PathParam("id") String id) {
        return workflow.content(account(), Inputs.uuid(id), "draft", null);
    }
    @GET @Path("/{id}/published") public Dtos.Content published(@PathParam("id") String id) {
        return workflow.content(account(), Inputs.uuid(id), "published", null);
    }
    @GET @Path("/{id}/revisions/{number}") public Dtos.Content historical(
        @PathParam("id") String id, @PathParam("number") Long number) {
        return workflow.content(account(), Inputs.uuid(id), "revision", number);
    }
    @GET @Path("/{id}/revisions") public List<Dtos.RevisionSummary> history(@PathParam("id") String id) {
        return workflow.history(account(), Inputs.uuid(id));
    }
}
