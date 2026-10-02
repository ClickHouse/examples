package example;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.LockModeType;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.WebApplicationException;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.UUID;

@ApplicationScoped
public class Workflow {
    private Document document(UUID account, UUID id, boolean lock) {
        var query = Document.<Document>find("accountId = ?1 and id = ?2", account, id);
        if (lock) query.withLock(LockModeType.PESSIMISTIC_WRITE);
        return query.firstResultOptional().orElseThrow(NotFoundException::new);
    }

    private Revision revision(UUID id, long number) {
        return Revision.<Revision>find("documentId = ?1 and number = ?2", id, number)
            .firstResultOptional().orElseThrow(NotFoundException::new);
    }

    @Transactional
    public Dtos.Summary create(UUID account, Dtos.Create input) {
        if (input == null) throw new BadRequestException("A JSON object is required");
        String title = Inputs.text(input.title(), 120, false);
        String body = Inputs.text(input.body(), 16_000, true);
        Document d = new Document();
        d.id = UUID.randomUUID();
        d.accountId = account;
        d.title = title;
        d.draftRevision = 1;
        d.createdAt = Instant.now().truncatedTo(ChronoUnit.MICROS);
        d.persistAndFlush(); // Deferred draft FK is checked at commit, after the revision exists.
        append(d, 1, title, body);
        return Dtos.Summary.from(d);
    }

    @Transactional
    public Dtos.Summary edit(UUID account, UUID id, Dtos.Edit input) {
        if (input == null) throw new BadRequestException("A JSON object is required");
        long expected = Inputs.version(input.expectedDraftRevision(), 1);
        String title = Inputs.text(input.title(), 120, false);
        String body = Inputs.text(input.body(), 16_000, true);
        Document d = document(account, id, true);
        if (d.draftRevision != expected) conflict("Draft changed; refetch before editing");
        if (d.draftRevision == Inputs.MAX_VERSION) conflict("Revision limit reached");
        long next = d.draftRevision + 1;
        append(d, next, title, body); // Flush this INSERT before moving the pointer.
        d.title = title;
        d.draftRevision = next;
        d.flush();
        return Dtos.Summary.from(d);
    }

    private void append(Document d, long number, String title, String body) {
        Revision r = new Revision();
        r.documentId = d.id;
        r.number = number;
        r.title = title;
        r.body = body;
        r.createdAt = Instant.now().truncatedTo(ChronoUnit.MICROS);
        r.persistAndFlush();
    }

    @Transactional
    public Dtos.Summary publish(UUID account, UUID id, Dtos.Publish input) {
        if (input == null) throw new BadRequestException("A JSON object is required");
        long expected = Inputs.version(input.expectedPublicationVersion(), 0);
        long selected = Inputs.version(input.revision(), 1);
        Document d = document(account, id, true);
        revision(d.id, selected); // Always scoped to this document, including replays.
        boolean same = d.publishedRevision != null && d.publishedRevision == selected;
        if (same && (expected == d.publicationVersion
            || (d.publicationVersion > 0 && expected == d.publicationVersion - 1))) {
            return Dtos.Summary.from(d);
        }
        if (expected != d.publicationVersion) conflict("Publication changed; refetch before publishing");
        if (d.publicationVersion == Inputs.MAX_VERSION) conflict("Publication limit reached");
        d.publishedRevision = selected;
        d.publicationVersion++;
        d.flush();
        return Dtos.Summary.from(d);
    }

    @Transactional
    public Dtos.Content content(UUID account, UUID id, String selection, Long number) {
        Document d = document(account, id, false);
        long chosen = switch (selection) {
            case "draft" -> d.draftRevision;
            case "published" -> {
                if (d.publishedRevision == null) throw new NotFoundException();
                yield d.publishedRevision;
            }
            case "revision" -> Inputs.version(number, 1);
            default -> throw new BadRequestException("Unknown content selection");
        };
        return Dtos.Content.from(revision(d.id, chosen));
    }

    @Transactional
    public List<Dtos.Summary> list(UUID account) {
        return Document.<Document>find("accountId = ?1 order by createdAt desc, id desc", account)
            .range(0, 19).list().stream().map(Dtos.Summary::from).toList();
    }

    @Transactional
    public List<Dtos.RevisionSummary> history(UUID account, UUID id) {
        document(account, id, false);
        return Revision.<Revision>find("documentId = ?1 order by number desc", id)
            .range(0, 99).list().stream()
            .map(r -> new Dtos.RevisionSummary(r.number, r.title, r.createdAt)).toList();
    }

    private static void conflict(String message) { throw new WebApplicationException(message, 409); }
}
