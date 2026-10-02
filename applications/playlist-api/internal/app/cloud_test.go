//go:build cloud

package app

import (
	"bytes"
	"context"
	"crypto/x509"
	"database/sql"
	"encoding/json"
	"entgo.io/ent/dialect"
	entsql "entgo.io/ent/dialect/sql"
	"errors"
	"example.com/playlist-api/ent"
	"example.com/playlist-api/graph/model"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestCloudTLS(t *testing.T) {
	base, err := Config()
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	positive, err := pgx.ConnectConfig(ctx, base)
	if err != nil {
		t.Fatal("verify-full positive failed")
	}
	positive.Close(ctx)
	wrongCA := base.Copy()
	wrongCA.TLSConfig = base.TLSConfig.Clone()
	wrongCA.TLSConfig.RootCAs, _ = x509.SystemCertPool()
	_, err = pgx.ConnectConfig(ctx, wrongCA)
	var authority x509.UnknownAuthorityError
	if !errors.As(err, &authority) {
		t.Fatalf("Expected x509.UnknownAuthorityError, got %T", err)
	}
	wrongName := base.Copy()
	wrongName.TLSConfig = base.TLSConfig.Clone()
	wrongName.TLSConfig.ServerName = "wrong-hostname.invalid"
	_, err = pgx.ConnectConfig(ctx, wrongName)
	var name x509.HostnameError
	if !errors.As(err, &name) {
		t.Fatalf("Expected x509.HostnameError, got %T", err)
	}
	t.Log("Actual pgx positive; CA UnknownAuthorityError; explicit wrong ServerName HostnameError. Default production verifier unchanged.")

}

type barrier struct {
	reached chan struct{}
	release chan struct{}
	once    sync.Once
}
type gatedDriver struct {
	countedDriver
	gate *barrier
}

func (d gatedDriver) BeginTx(ctx context.Context, options *sql.TxOptions) (dialect.Tx, error) {
	tx, err := d.countedDriver.BeginTx(ctx, options)
	if err != nil {
		return nil, err
	}
	return gatedTx{tx, d.gate}, nil
}

type gatedTx struct {
	dialect.Tx
	gate *barrier
}

func (tx gatedTx) Query(ctx context.Context, q string, args, v any) error {
	err := tx.Tx.Query(ctx, q, args, v)
	if err == nil && strings.Contains(q, `"playlists"`) {
		tx.gate.once.Do(func() {
			close(tx.gate.reached)
			select {
			case <-tx.gate.release:
			case <-ctx.Done():
			}
		})
	}
	return err
}
func postCloud(t *testing.T, query string, variables any) *model.Playlist {
	t.Helper()
	body, _ := json.Marshal(map[string]any{"query": query, "variables": variables})
	request, _ := http.NewRequest("POST", "http://127.0.0.1:8080/query", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Authorization", "Bearer "+os.Getenv("ACCOUNT_A_TOKEN"))
	response, err := (&http.Client{Timeout: 35 * time.Second}).Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(response.Body, 1048576))
	if err != nil {
		t.Fatal(err)
	}
	var decoded struct {
		Data   map[string]*model.Playlist
		Errors []any
	}
	if json.Unmarshal(raw, &decoded) != nil || len(decoded.Errors) > 0 || len(decoded.Data) != 1 {
		t.Fatal("GraphQL fixture failed", response.StatusCode)
	}
	for _, playlist := range decoded.Data {
		return playlist
	}
	t.Fatal("No result")
	return nil
}
func TestCloudEagerReadCoherence(t *testing.T) {
	fields := "id name revision items{position track{id title artist durationSeconds}}"
	original := postCloud(t, "mutation($input:CreatePlaylistInput!){createPlaylist(input:$input){"+fields+"}}", map[string]any{"input": map[string]any{"name": "Coherence " + uuid.NewString(), "trackIds": []string{"10000000-0000-4000-8000-000000000001", "10000000-0000-4000-8000-000000000002"}}})
	client, db, err := Open()
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	gate := &barrier{reached: make(chan struct{}), release: make(chan struct{})}
	var releaseOnce sync.Once
	release := func() { releaseOnce.Do(func() { close(gate.release) }) }
	defer release()
	gated := ent.NewClient(ent.Driver(gatedDriver{countedDriver{entsql.OpenDB(dialect.Postgres, db)}, gate}))
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	ctx = WithOwner(ctx, uuid.MustParse("00000000-0000-4000-8000-000000000001"))
	ctx, count := WithCounter(ctx)
	tx, err := gated.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelRepeatableRead, ReadOnly: true})
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	ctx = ent.NewContext(ctx, tx.Client())
	type answer struct {
		row *model.Playlist
		err error
	}
	done := make(chan answer, 1)
	go func() { row, err := Read(ctx, original.ID); done <- answer{row, err} }()
	select {
	case <-gate.reached:
	case <-ctx.Done():
		t.Fatal("Header SELECT barrier not reached")
	}
	changed := postCloud(t, "mutation($input:ReorderInput!){reorderPlaylist(input:$input){"+fields+"}}", map[string]any{"input": map[string]any{"id": original.ID, "expectedRevision": 1, "trackIds": []string{original.Items[1].Track.ID, original.Items[0].Track.ID}}})
	if changed.Revision != 2 {
		t.Fatal("Writer did not commit revision2")
	}
	release()
	result := <-done
	if result.err != nil {
		t.Fatal(result.err)
	}
	if result.row.Revision != 1 || result.row.Items[0].Track.ID != original.Items[0].Track.ID || result.row.Items[1].Track.ID != original.Items[1].Track.ID {
		t.Fatal("Mixed header/items snapshot")
	}
	if count.Load() != 3 {
		t.Fatal("Expected three actual eager SELECTs", count.Load())
	}
	if err := tx.Commit(); err != nil {
		t.Fatal(err)
	}
	latest := postCloud(t, "query($id:ID!){playlist(id:$id){"+fields+"}}", map[string]any{"id": original.ID})
	if latest.Revision != 2 || latest.Items[0].Track.ID != original.Items[1].Track.ID {
		t.Fatal("Latest snapshot missing committed reorder")
	}
	t.Log("Actual first header SELECT paused; competing HTTP reorder committed; subsequent item/track SELECTs retained revision1 old order, fresh query sees revision2 swapped order. Exactly3 eager statements.")
}
