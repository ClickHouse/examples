//go:build integration

package inbox

import (
	"context"
	"crypto/x509"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

const integrationA = "00000000-0000-4000-8000-000000000001"
const integrationB = "00000000-0000-4000-8000-000000000002"

func testPool(t *testing.T, user, password string) *pgxpool.Pool {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	pool, err := OpenPool(ctx, user, password)
	if err != nil {
		t.Fatal(err)
	}
	return pool
}
func requiredTest(t *testing.T, key string) string {
	t.Helper()
	value := os.Getenv(key)
	if value == "" {
		t.Fatalf("missing %s; use a dedicated Cloud test service", key)
	}
	return value
}

func TestCloudWorkflow(t *testing.T) {
	tokens, err := ParseTokens(requiredTest(t, "INTEGRATION_TOKENS"))
	if err != nil {
		t.Fatal(err)
	}
	var rawTokens map[string]string
	_ = json.Unmarshal([]byte(os.Getenv("INTEGRATION_TOKENS")), &rawTokens)
	tokenA, tokenB := rawTokens[integrationA], rawTokens[integrationB]
	if tokenA == "" || tokenB == "" {
		t.Fatal("tests need both seeded integration tokens")
	}
	receiver := testPool(t, "", "")
	defer receiver.Close()
	writer := testPool(t, "webhook_migrator", requiredTest(t, "TEST_MIGRATOR_PASSWORD"))
	defer writer.Close()
	workerPool := testPool(t, "webhook_worker", requiredTest(t, "TEST_WORKER_PASSWORD"))
	defer workerPool.Close()
	worker := Worker{Pool: workerPool}
	ctx := context.Background()
	reset := func() {
		t.Helper()
		if _, err := writer.Exec(ctx, "TRUNCATE webhook.activity, webhook.events; UPDATE webhook.counters SET event_count = 0"); err != nil {
			t.Fatal(err)
		}
	}
	reset()
	defer reset()
	api, err := NewAPI(ctx, receiver, tokens)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(api.Handler())
	defer server.Close()
	request := func(method, path, token, id, body string) (int, map[string]any) {
		t.Helper()
		req, _ := http.NewRequest(method, server.URL+path, strings.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Event-ID", id)
		response, err := server.Client().Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		var result map[string]any
		if err = json.NewDecoder(response.Body).Decode(&result); err != nil {
			t.Fatal(err)
		}
		return response.StatusCode, result
	}
	receive := func(token, id, body string) map[string]any {
		t.Helper()
		code, bodyMap := request("POST", "/events", token, id, body)
		if code != 202 {
			t.Fatalf("receive returned %d: %v", code, bodyMap)
		}
		return bodyMap
	}
	stats := func() (int64, int64) {
		t.Helper()
		var count, activity int64
		if err := writer.QueryRow(ctx, "SELECT sum(event_count) FROM webhook.counters").Scan(&count); err != nil {
			t.Fatal(err)
		}
		if err := writer.QueryRow(ctx, "SELECT count(*) FROM webhook.activity").Scan(&activity); err != nil {
			t.Fatal(err)
		}
		return count, activity
	}
	body := `{"kind":"page_view","path":"/pricing"}`

	t.Run("concurrent identical deliveries persist one event and effect", func(t *testing.T) {
		reset()
		var wait sync.WaitGroup
		codes := make(chan int, 16)
		for i := 0; i < 16; i++ {
			wait.Add(1)
			go func() {
				defer wait.Done()
				code, _ := request("POST", "/events", tokenA, "delivery-1", body)
				codes <- code
			}()
		}
		wait.Wait()
		close(codes)
		for code := range codes {
			if code != 202 {
				t.Fatalf("duplicate returned %d", code)
			}
		}
		var rows int
		_ = writer.QueryRow(ctx, "SELECT count(*) FROM webhook.events").Scan(&rows)
		if rows != 1 {
			t.Fatalf("persisted %d events", rows)
		}
		worked, err := worker.ProcessOne(ctx)
		if err != nil || !worked {
			t.Fatalf("worker: %t %v", worked, err)
		}
		count, activity := stats()
		if count != 1 || activity != 1 {
			t.Fatalf("durable effects %d/%d", count, activity)
		}
		replay := receive(tokenA, "delivery-1", body)
		if replay["replayed"] != true || replay["event"].(map[string]any)["status"] != "processed" {
			t.Fatalf("bad completed replay: %v", replay)
		}
	})
	t.Run("integration scopes, byte conflicts and forbidden reads", func(t *testing.T) {
		reset()
		receive(tokenA, "shared-id", body)
		receive(tokenB, "shared-id", body)
		code, _ := request("POST", "/events", tokenA, "shared-id", `{"kind":"page_view","path":"/different"}`)
		if code != 409 {
			t.Fatalf("conflict %d", code)
		}
		code, _ = request("POST", "/events", tokenA, "shared-id", body+" ")
		if code != 409 {
			t.Fatalf("byte conflict %d", code)
		}
		receive(tokenA, "only-a", body)
		code, _ = request("GET", "/events/only-a?integration_id="+integrationA, tokenB, "", "")
		if code != 404 {
			t.Fatalf("cross-integration read %d", code)
		}
		code, _ = request("GET", "/events/only-a", "wrong", "", "")
		if code != 401 {
			t.Fatalf("wrong token %d", code)
		}
		var count int
		_ = writer.QueryRow(ctx, "SELECT count(*) FROM webhook.events WHERE external_event_id = 'shared-id'").Scan(&count)
		if count != 2 {
			t.Fatalf("shared ID has %d rows", count)
		}
		for i := 0; i < 3; i++ {
			if worked, err := worker.ProcessOne(ctx); err != nil || !worked {
				t.Fatalf("scoped processing: %t %v", worked, err)
			}
		}
		_, statsA := request("GET", "/stats", tokenA, "", "")
		_, statsB := request("GET", "/stats", tokenB, "", "")
		if statsA["processed_events"] != float64(2) || statsB["processed_events"] != float64(1) {
			t.Fatalf("unscoped stats: %v / %v", statsA, statsB)
		}
	})
	t.Run("invalid input and streamed oversized body rejected", func(t *testing.T) {
		reset()
		for _, payload := range []string{`{"kind":"bad","path":"/"}`, `{"kind":"page_view","path":"relative"}`, `{"kind":"page_view","path":"/","integration_id":"x"}`, `{} {}`} {
			code, _ := request("POST", "/events", tokenA, "invalid", payload)
			if code != 400 {
				t.Fatalf("input accepted %d", code)
			}
		}
		for _, id := range []string{"", strings.Repeat("a", 81), "invalid/id"} {
			code, _ := request("POST", "/events", tokenA, id, body)
			if code != 400 {
				t.Fatalf("ID accepted %d", code)
			}
		}
		req, _ := http.NewRequest("POST", server.URL+"/events", io.NopCloser(strings.NewReader(strings.Repeat("x", 4097))))
		req.ContentLength = -1
		req.Header.Set("Authorization", "Bearer "+tokenA)
		req.Header.Set("X-Event-ID", "oversized")
		req.Header.Set("Content-Type", "application/json")
		response, err := server.Client().Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()
		if response.StatusCode != 413 {
			t.Fatalf("oversized %d", response.StatusCode)
		}
		var rows int
		_ = writer.QueryRow(ctx, "SELECT count(*) FROM webhook.events").Scan(&rows)
		if rows != 0 {
			t.Fatal("invalid requests persisted data")
		}
	})
	t.Run("four competing workers process every event once", func(t *testing.T) {
		reset()
		for i := 0; i < 24; i++ {
			receive(tokenA, fmt.Sprintf("batch-%02d", i), body)
		}
		var wait sync.WaitGroup
		errorsCh := make(chan error, 4)
		for i := 0; i < 4; i++ {
			wait.Add(1)
			go func() {
				defer wait.Done()
				for {
					worked, err := worker.ProcessOne(ctx)
					if err != nil {
						errorsCh <- err
						return
					}
					if !worked {
						return
					}
				}
			}()
		}
		wait.Wait()
		close(errorsCh)
		for err := range errorsCh {
			t.Fatal(err)
		}
		count, activity := stats()
		if count != 24 || activity != 24 {
			t.Fatalf("effects %d/%d", count, activity)
		}
		var wrong int
		_ = writer.QueryRow(ctx, "SELECT count(*) FROM webhook.events WHERE status <> 'processed' OR attempts <> 1").Scan(&wrong)
		if wrong != 0 {
			t.Fatalf("%d incorrect states", wrong)
		}
	})
	t.Run("processing failures retry at bounded delays and end terminal", func(t *testing.T) {
		reset()
		receive(tokenA, "failure", `{"kind":"demo_failure","path":"/demo"}`)
		for attempt := 1; attempt <= 3; attempt++ {
			worked, err := worker.ProcessOne(ctx)
			if err != nil || !worked {
				t.Fatalf("attempt %d: %t %v", attempt, worked, err)
			}
			code, event := request("GET", "/events/failure", tokenA, "", "")
			if code != 200 || event["attempts"] != float64(attempt) {
				t.Fatalf("attempt state %v", event)
			}
			if attempt < 3 {
				worked, err = worker.ProcessOne(ctx)
				if err != nil || worked {
					t.Fatalf("retry backoff missing: %t %v", worked, err)
				}
				time.Sleep(time.Duration(attempt)*time.Second + 100*time.Millisecond)
			} else if event["status"] != "failed" || event["last_error"] == nil {
				t.Fatalf("terminal state %v", event)
			}
		}
		worked, err := worker.ProcessOne(ctx)
		if err != nil || worked {
			t.Fatal("terminal event claimed")
		}
		count, activity := stats()
		if count != 0 || activity != 0 {
			t.Fatal("failed event has effects")
		}
	})
	t.Run("rollback after effects keeps event pending and counter unchanged", func(t *testing.T) {
		reset()
		receive(tokenA, "rollback", body)
		_, err := worker.processOne(ctx, func() error { return errors.New("abort before commit") })
		if err == nil {
			t.Fatal("rollback hook did not fail")
		}
		count, activity := stats()
		if count != 0 || activity != 0 {
			t.Fatal("rollback leaked effects")
		}
		_, event := request("GET", "/events/rollback", tokenA, "", "")
		if event["status"] != "pending" || event["attempts"] != float64(0) {
			t.Fatal("rollback leaked attempt")
		}
		worked, err := worker.ProcessOne(ctx)
		if err != nil || !worked {
			t.Fatal("rollback not recoverable")
		}
		count, activity = stats()
		if count != 1 || activity != 1 {
			t.Fatal("recovery effects wrong")
		}
	})
	t.Run("actual worker process loss releases claim and rolls back effects", func(t *testing.T) {
		reset()
		receive(tokenA, "crash", body)
		marker := filepath.Join(t.TempDir(), "before-commit")
		child := exec.Command(os.Args[0], "-test.run=^TestCrashWorkerHelper$")
		child.Env = append(os.Environ(), "WEBHOOK_TEST_CRASH_MARKER="+marker)
		if err := child.Start(); err != nil {
			t.Fatal(err)
		}
		defer child.Process.Kill()
		deadline := time.Now().Add(8 * time.Second)
		for {
			if _, err := os.Stat(marker); err == nil {
				break
			}
			if time.Now().After(deadline) {
				t.Fatal("child did not reach pre-commit point")
			}
			time.Sleep(20 * time.Millisecond)
		}
		count, activity := stats()
		if count != 0 || activity != 0 {
			t.Fatal("uncommitted effects visible")
		}
		worked, err := worker.ProcessOne(ctx)
		if err != nil || worked {
			t.Fatalf("locked event not skipped: %t %v", worked, err)
		}
		_ = child.Process.Kill()
		_ = child.Wait()
		deadline = time.Now().Add(5 * time.Second)
		for {
			worked, err = worker.ProcessOne(ctx)
			if err != nil {
				t.Fatal(err)
			}
			if worked {
				break
			}
			if time.Now().After(deadline) {
				t.Fatal("crashed claim not released")
			}
			time.Sleep(50 * time.Millisecond)
		}
		count, activity = stats()
		if count != 1 || activity != 1 {
			t.Fatal("process recovery effect wrong")
		}
	})
	t.Run("restricted roles and strict TLS", func(t *testing.T) {
		for _, statement := range []string{"UPDATE webhook.events SET status = 'failed'", "UPDATE webhook.counters SET event_count = 0", "CREATE TABLE webhook.denied (id INTEGER)", "SELECT * FROM webhook.schema_migrations"} {
			_, err := receiver.Exec(ctx, statement)
			var failure *pgconn.PgError
			if !errors.As(err, &failure) || failure.Code != "42501" {
				t.Fatalf("receiver permission: %s %v", statement, err)
			}
		}
		_, err := workerPool.Exec(ctx, "UPDATE webhook.events SET payload = '{}'::jsonb")
		var failure *pgconn.PgError
		if !errors.As(err, &failure) || failure.Code != "42501" {
			t.Fatalf("worker changed payload: %v", err)
		}
		for _, kind := range []string{"ca", "host"} {
			cfg, err := PoolConfig("", "")
			if err != nil {
				t.Fatal(err)
			}
			if kind == "ca" {
				cert, err := os.ReadFile(requiredTest(t, "TEST_WRONG_CA"))
				if err != nil {
					t.Fatal(err)
				}
				roots := x509.NewCertPool()
				roots.AppendCertsFromPEM(cert)
				cfg.ConnConfig.TLSConfig.RootCAs = roots
			} else {
				cfg.ConnConfig.TLSConfig.ServerName = "wrong.invalid"
			}
			conn, err := pgx.ConnectConfig(ctx, cfg.ConnConfig)
			if err == nil {
				conn.Close(ctx)
				t.Fatalf("wrong %s accepted", kind)
			}
			if kind == "host" {
				var hostError x509.HostnameError
				if !errors.As(err, &hostError) {
					t.Fatalf("expected hostname error: %v", err)
				}
			} else {
				var caError x509.UnknownAuthorityError
				if !errors.As(err, &caError) {
					t.Fatalf("expected CA error: %v", err)
				}
			}
		}
	})
	t.Run("receiver and pool recreation retains accepted status", func(t *testing.T) {
		reset()
		receive(tokenA, "restart", body)
		server.Close()
		receiver.Close()
		receiver = testPool(t, "", "")
		defer receiver.Close()
		api, err := NewAPI(ctx, receiver, tokens)
		if err != nil {
			t.Fatal(err)
		}
		server = httptest.NewServer(api.Handler())
		defer server.Close()
		code, event := request("GET", "/events/restart", tokenA, "", "")
		if code != 200 || event["status"] != "pending" {
			t.Fatalf("persistence %v", event)
		}
		worker.ProcessOne(ctx)
		code, event = request("GET", "/events/restart", tokenA, "", "")
		if code != 200 || event["status"] != "processed" {
			t.Fatalf("processing after recreation %v", event)
		}
	})
}

// This child is invoked only by the process-loss test; it never changes the CLI.
func TestCrashWorkerHelper(t *testing.T) {
	marker := os.Getenv("WEBHOOK_TEST_CRASH_MARKER")
	if marker == "" {
		t.Skip("crash helper")
	}
	pool := testPool(t, "webhook_worker", requiredTest(t, "TEST_WORKER_PASSWORD"))
	defer pool.Close()
	_, err := (Worker{Pool: pool}).processOne(context.Background(), func() error {
		if err := os.WriteFile(marker, []byte("uncommitted"), 0600); err != nil {
			return err
		}
		select {} // Parent kills this process while the database transaction is open.
	})
	t.Fatalf("crash helper returned unexpectedly: %v", err)
}
