-- The dedicated schema is created by sql/001_roles.sql and owned by the migration role.
CREATE TYPE "feature_board"."RequestStatus" AS ENUM ('OPEN', 'PLANNED', 'IN_PROGRESS', 'SHIPPED');

CREATE TABLE "feature_board"."feature_requests" (
    "id" UUID NOT NULL,
    "title" VARCHAR(120) NOT NULL,
    "description" VARCHAR(4000) NOT NULL,
    "author_id" VARCHAR(255) NOT NULL,
    "author_name" VARCHAR(80) NOT NULL,
    "status" "feature_board"."RequestStatus" NOT NULL DEFAULT 'OPEN',
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,
    CONSTRAINT "feature_requests_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "feature_requests_title_length" CHECK (char_length(btrim("title")) BETWEEN 8 AND 120),
    CONSTRAINT "feature_requests_description_length" CHECK (char_length(btrim("description")) BETWEEN 20 AND 4000)
);

CREATE TABLE "feature_board"."votes" (
    "request_id" UUID NOT NULL,
    "user_id" VARCHAR(255) NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "votes_pkey" PRIMARY KEY ("request_id", "user_id"),
    CONSTRAINT "votes_request_id_fkey" FOREIGN KEY ("request_id")
      REFERENCES "feature_board"."feature_requests"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "feature_requests_status_created_at_id_idx"
  ON "feature_board"."feature_requests"("status", "created_at" DESC, "id" DESC);
CREATE INDEX "feature_requests_created_at_id_idx"
  ON "feature_board"."feature_requests"("created_at" DESC, "id" DESC);
