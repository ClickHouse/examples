package inbox

import (
	"context"
	"fmt"
	migrations "github.com/ClickHouse/examples/applications/webhook-inbox/sql"
	"github.com/jackc/pgx/v5/pgxpool"
)

func Migrate(ctx context.Context, pool *pgxpool.Pool, down bool) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(context.Background())
	if _, err = tx.Exec(ctx, "SELECT pg_advisory_xact_lock(72641002)"); err != nil {
		return err
	}
	if _, err = tx.Exec(ctx, "CREATE TABLE IF NOT EXISTS webhook.schema_migrations (version INTEGER PRIMARY KEY)"); err != nil {
		return err
	}
	var exists bool
	if err = tx.QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM webhook.schema_migrations WHERE version = 1)").Scan(&exists); err != nil {
		return err
	}
	if down && exists {
		raw, _ := migrations.Files.ReadFile("down.sql")
		if _, err = tx.Exec(ctx, string(raw)); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, "DELETE FROM webhook.schema_migrations WHERE version = 1")
	} else if !down && !exists {
		raw, _ := migrations.Files.ReadFile("001_initial.sql")
		if _, err = tx.Exec(ctx, string(raw)); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, "INSERT INTO webhook.schema_migrations (version) VALUES (1)")
	}
	if err != nil {
		return err
	}
	return tx.Commit(ctx)
}
func Seed(ctx context.Context, pool *pgxpool.Pool) error {
	raw, err := migrations.Files.ReadFile("seed.sql")
	if err != nil {
		return fmt.Errorf("read seed: %w", err)
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(context.Background())
	if _, err = tx.Exec(ctx, string(raw)); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
