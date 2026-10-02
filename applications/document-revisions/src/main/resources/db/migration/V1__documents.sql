CREATE TABLE revision_api.accounts (
    id uuid PRIMARY KEY,
    name text NOT NULL CHECK (length(name) BETWEEN 1 AND 120)
);

CREATE TABLE revision_api.documents (
    id uuid PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES revision_api.accounts(id),
    title text NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
    draft_revision bigint NOT NULL CHECK (draft_revision BETWEEN 1 AND 1000000000),
    published_revision bigint CHECK (published_revision BETWEEN 1 AND 1000000000),
    publication_version bigint NOT NULL DEFAULT 0 CHECK (publication_version BETWEEN 0 AND 1000000000),
    created_at timestamptz NOT NULL,
    CHECK ((published_revision IS NULL) = (publication_version = 0))
);

CREATE TABLE revision_api.revisions (
    document_id uuid NOT NULL REFERENCES revision_api.documents(id),
    number bigint NOT NULL CHECK (number BETWEEN 1 AND 1000000000),
    title text NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
    body text NOT NULL CHECK (length(body) BETWEEN 1 AND 16000),
    created_at timestamptz NOT NULL,
    PRIMARY KEY (document_id, number)
);

ALTER TABLE revision_api.documents
    ADD CONSTRAINT draft_same_document FOREIGN KEY (id, draft_revision)
        REFERENCES revision_api.revisions(document_id, number) DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT published_same_document FOREIGN KEY (id, published_revision)
        REFERENCES revision_api.revisions(document_id, number) DEFERRABLE INITIALLY DEFERRED;

CREATE INDEX documents_by_account ON revision_api.documents(account_id, created_at DESC, id DESC);

GRANT SELECT ON revision_api.accounts TO revision_app;
GRANT SELECT, INSERT ON revision_api.documents TO revision_app;
GRANT UPDATE (title, draft_revision, published_revision, publication_version)
    ON revision_api.documents TO revision_app;
GRANT SELECT, INSERT ON revision_api.revisions TO revision_app;
