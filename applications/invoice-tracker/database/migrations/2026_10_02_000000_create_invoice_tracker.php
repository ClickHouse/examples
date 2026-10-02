<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('users', function (Blueprint $table) {
            $table->id();
            $table->string('name', 80);
            $table->string('email', 254)->unique();
            $table->string('password');
            $table->timestamps();
        });
        Schema::create('sessions', function (Blueprint $table) {
            $table->string('id')->primary();
            $table->foreignId('user_id')->nullable()->index();
            $table->string('ip_address', 45)->nullable();
            $table->text('user_agent')->nullable();
            $table->text('payload');
            $table->integer('last_activity')->index();
        });
        Schema::create('invoices', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained();
            $table->string('recipient', 120);
            $table->string('reference', 120);
            $table->string('currency', 3)->default('USD');
            $table->string('status', 10)->default('draft');
            $table->string('public_number', 40)->nullable()->unique();
            $table->bigInteger('issued_total_cents')->nullable();
            $table->jsonb('snapshot')->nullable();
            $table->timestampTz('issued_at')->nullable();
            $table->timestampTz('settled_at')->nullable();
            $table->timestamps();
            $table->index(['user_id', 'id']);
        });
        Schema::create('invoice_lines', function (Blueprint $table) {
            $table->id();
            $table->foreignId('invoice_id')->constrained();
            $table->string('description', 200);
            $table->integer('quantity');
            $table->bigInteger('unit_cents');
            $table->integer('position');
            $table->unique(['invoice_id', 'position']);
        });
        DB::unprepared(<<<'SQL'
CREATE SEQUENCE invoice_tracker.invoice_public_number;
ALTER TABLE invoice_tracker.invoices ADD CONSTRAINT invoice_lifecycle CHECK (
    currency='USD' AND length(btrim(recipient)) BETWEEN 1 AND 120
    AND length(btrim(reference)) BETWEEN 1 AND 120 AND (
    (status='draft' AND public_number IS NULL AND issued_total_cents IS NULL AND snapshot IS NULL AND issued_at IS NULL AND settled_at IS NULL)
    OR (status IN ('issued','settled') AND public_number IS NOT NULL
        AND issued_total_cents IS NOT NULL AND issued_total_cents BETWEEN 0 AND 10000000000000
        AND snapshot IS NOT NULL AND jsonb_typeof(snapshot)='object' AND issued_at IS NOT NULL
        AND ((status='issued' AND settled_at IS NULL) OR (status='settled' AND settled_at IS NOT NULL)))
));
ALTER TABLE invoice_tracker.invoice_lines ADD CONSTRAINT invoice_line_bounds CHECK (
    quantity BETWEEN 1 AND 1000 AND unit_cents BETWEEN 0 AND 100000000
    AND position BETWEEN 0 AND 99 AND length(btrim(description)) BETWEEN 1 AND 200
);
CREATE FUNCTION invoice_tracker.guard_invoice_snapshot() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
        RAISE EXCEPTION 'Invoice owner cannot change' USING ERRCODE='23514';
    END IF;
    IF OLD.status <> 'draft' THEN
        IF (NEW.recipient,NEW.reference,NEW.currency,NEW.public_number,NEW.issued_total_cents,NEW.snapshot,NEW.issued_at)
            IS DISTINCT FROM (OLD.recipient,OLD.reference,OLD.currency,OLD.public_number,OLD.issued_total_cents,OLD.snapshot,OLD.issued_at)
        THEN RAISE EXCEPTION 'Issued invoice snapshot is immutable' USING ERRCODE='23514'; END IF;
        IF NEW.status NOT IN ('issued','settled') OR (OLD.status='settled' AND NEW.status<>'settled')
            OR (OLD.status='settled' AND NEW.settled_at IS DISTINCT FROM OLD.settled_at)
        THEN RAISE EXCEPTION 'Invalid invoice transition' USING ERRCODE='23514'; END IF;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER immutable_invoice_snapshot BEFORE UPDATE ON invoice_tracker.invoices
    FOR EACH ROW EXECUTE FUNCTION invoice_tracker.guard_invoice_snapshot();
CREATE FUNCTION invoice_tracker.guard_draft_lines() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE parent_id bigint; parent_status text;
BEGIN
    IF TG_OP='UPDATE' AND NEW.invoice_id IS DISTINCT FROM OLD.invoice_id THEN
        RAISE EXCEPTION 'Line parent cannot change' USING ERRCODE='23514';
    END IF;
    parent_id := CASE WHEN TG_OP='DELETE' THEN OLD.invoice_id ELSE NEW.invoice_id END;
    SELECT status INTO parent_status FROM invoice_tracker.invoices WHERE id=parent_id FOR UPDATE;
    IF parent_status IS DISTINCT FROM 'draft' THEN
        RAISE EXCEPTION 'Issued invoice lines are immutable' USING ERRCODE='23514';
    END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER draft_invoice_lines BEFORE INSERT OR UPDATE OR DELETE ON invoice_tracker.invoice_lines
    FOR EACH ROW EXECUTE FUNCTION invoice_tracker.guard_draft_lines();
SQL);
    }

    public function down(): void
    {
        Schema::dropIfExists('invoice_lines');
        Schema::dropIfExists('invoices');
        Schema::dropIfExists('sessions');
        Schema::dropIfExists('users');
        DB::unprepared('DROP FUNCTION invoice_tracker.guard_draft_lines(); DROP FUNCTION invoice_tracker.guard_invoice_snapshot(); DROP SEQUENCE invoice_tracker.invoice_public_number;');
    }
};
