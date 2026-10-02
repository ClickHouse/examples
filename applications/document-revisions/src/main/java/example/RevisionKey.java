package example;

import java.io.Serializable;
import java.util.Objects;
import java.util.UUID;

public class RevisionKey implements Serializable {
    public UUID documentId;
    public long number;
    public RevisionKey() {}
    public RevisionKey(UUID documentId, long number) {
        this.documentId = documentId;
        this.number = number;
    }
    @Override public boolean equals(Object other) {
        return other instanceof RevisionKey key && number == key.number
            && Objects.equals(documentId, key.documentId);
    }
    @Override public int hashCode() { return Objects.hash(documentId, number); }
}
