package example;

import java.time.Instant;
import java.util.UUID;

public final class Dtos {
    private Dtos() {}
    public record Create(String title, String body) {}
    public record Edit(Long expectedDraftRevision, String title, String body) {}
    public record Publish(Long expectedPublicationVersion, Long revision) {}
    public record Summary(UUID id, String title, long draftRevision, Long publishedRevision,
                          long publicationVersion, Instant createdAt) {
        public static Summary from(Document d) {
            return new Summary(d.id, d.title, d.draftRevision, d.publishedRevision,
                d.publicationVersion, d.createdAt);
        }
    }
    public record Content(UUID documentId, long revision, String title, String body, Instant createdAt) {
        public static Content from(Revision r) {
            return new Content(r.documentId, r.number, r.title, r.body, r.createdAt);
        }
    }
    public record RevisionSummary(long revision, String title, Instant createdAt) {}
    public record Error(String message) {}
}
