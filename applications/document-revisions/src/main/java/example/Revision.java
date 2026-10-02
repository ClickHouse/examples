package example;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.*;
import org.hibernate.annotations.Immutable;
import java.time.Instant;
import java.util.UUID;

@Entity
@Immutable
@IdClass(RevisionKey.class)
@Table(name = "revisions", schema = "revision_api")
public class Revision extends PanacheEntityBase {
    @Id @Column(name = "document_id") public UUID documentId;
    @Id public long number;
    @Column(nullable = false) public String title;
    @Column(nullable = false, columnDefinition = "text") public String body;
    @Column(name = "created_at", nullable = false) public Instant createdAt;
}
