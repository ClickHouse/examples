package example;

import io.quarkus.security.AuthenticationFailedException;
import io.quarkus.security.identity.IdentityProviderManager;
import io.quarkus.security.identity.SecurityIdentity;
import io.quarkus.security.runtime.QuarkusSecurityIdentity;
import io.quarkus.vertx.http.runtime.security.*;
import io.smallrye.mutiny.Uni;
import io.vertx.ext.web.RoutingContext;
import jakarta.annotation.PostConstruct;
import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

@ApplicationScoped
public class BearerAuth implements HttpAuthenticationMechanism {
    @ConfigProperty(name = "accounts.first-token") String first;
    @ConfigProperty(name = "accounts.second-token") String second;
    @PostConstruct void validate() {
        if (!first.matches("[0-9a-f]{64}") || !second.matches("[0-9a-f]{64}") || first.equals(second)) {
            throw new IllegalStateException("Configure two distinct 256-bit hex account tokens");
        }
    }
    @Override public Uni<SecurityIdentity> authenticate(RoutingContext context, IdentityProviderManager ignored) {
        String header = context.request().getHeader("Authorization");
        if (header == null) return Uni.createFrom().nullItem();
        if (!header.matches("Bearer [0-9a-f]{64}")) return Uni.createFrom().failure(new AuthenticationFailedException());
        byte[] supplied = header.substring(7).getBytes(StandardCharsets.US_ASCII);
        boolean one = MessageDigest.isEqual(supplied, first.getBytes(StandardCharsets.US_ASCII));
        boolean two = MessageDigest.isEqual(supplied, second.getBytes(StandardCharsets.US_ASCII));
        if (!one && !two) return Uni.createFrom().failure(new AuthenticationFailedException());
        String account = one ? "00000000-0000-0000-0000-000000000001" : "00000000-0000-0000-0000-000000000002";
        return Uni.createFrom().item(QuarkusSecurityIdentity.builder().setPrincipal(() -> account).build());
    }
    @Override public Uni<ChallengeData> getChallenge(RoutingContext context) {
        return Uni.createFrom().item(new ChallengeData(401, "WWW-Authenticate", "Bearer"));
    }
    @Override public Uni<HttpCredentialTransport> getCredentialTransport(RoutingContext context) {
        return Uni.createFrom().item(new HttpCredentialTransport(HttpCredentialTransport.Type.AUTHORIZATION, "Bearer"));
    }
}
