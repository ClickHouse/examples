package example;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "documents", schema = "revision_api")
public class Document extends PanacheEntityBase {
    @Id public UUID id;
    @Column(name = "account_id", nullable = false, updatable = false) public UUID accountId;
    @Column(nullable = false) public String title;
    @Column(name = "draft_revision", nullable = false) public long draftRevision;
    @Column(name = "published_revision") public Long publishedRevision;
    @Column(name = "publication_version", nullable = false) public long publicationVersion;
    @Column(name = "created_at", nullable = false, updatable = false) public Instant createdAt;
}
