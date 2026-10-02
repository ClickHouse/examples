package inbox

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/ClickHouse/examples/applications/webhook-inbox/internal/store"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Worker struct{ Pool *pgxpool.Pool }

func (worker Worker) ProcessOne(ctx context.Context) (bool, error) {
	return worker.processOne(ctx, nil)
}
func (worker Worker) processOne(ctx context.Context, beforeCommit func() error) (bool, error) {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	tx, err := worker.Pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.ReadCommitted})
	if err != nil {
		return false, err
	}
	defer tx.Rollback(context.Background())
	queries := store.New(worker.Pool).WithTx(tx)
	event, err := queries.ClaimEvent(ctx)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	payload, parseErr := ParsePayload(event.Payload)
	if parseErr != nil || payload.Kind == "demo_failure" {
		err = queries.FailEvent(ctx, store.FailEventParams{ID: event.ID, LastError: pgtype.Text{String: "Demo processor rejected this event", Valid: true}})
	} else {
		err = queries.RecordActivity(ctx, store.RecordActivityParams{EventID: event.ID, IntegrationID: event.IntegrationID, Path: payload.Path})
		if err == nil {
			var affected int64
			affected, err = queries.IncrementCounter(ctx, event.IntegrationID)
			if err == nil && affected != 1 {
				err = fmt.Errorf("integration counter is missing")
			}
		}
		if err == nil {
			err = queries.CompleteEvent(ctx, event.ID)
		}
	}
	if err != nil {
		return false, err
	} // SQL/connection failure rolls back all effects and the attempt.
	// Test-only hook exercises rollback and actual process loss after DB effects.
	if beforeCommit != nil {
		if err = beforeCommit(); err != nil {
			return false, err
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return false, err
	}
	return true, nil
}
