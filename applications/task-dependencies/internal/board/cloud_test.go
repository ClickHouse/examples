package board

import (
	"context"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"github.com/jackc/pgx/v5"
	"gorm.io/gorm"
	"net/http"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func cloud(t *testing.T) {
	t.Helper()
	if os.Getenv("TASKS_CLOUD_TESTS") != "1" {
		t.Skip("requires disposable real Cloud fixture")
	}
}
func TestCloudGORMTLS(t *testing.T) {
	cloud(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	config, err := pgx.ParseConfig("")
	if err != nil {
		t.Fatal(err)
	}
	db, pool, err := openConfig(ctx, config)
	if err != nil {
		t.Fatal("official CA positive failed")
	}
	defer pool.Close()
	var ssl bool
	if err = db.Raw("SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()").Scan(&ssl).Error; err != nil || !ssl {
		t.Fatal("actual GORM connection has no observed TLS", err)
	}
	for _, control := range []string{"wrong CA", "wrong hostname"} {
		changed := config.Copy()
		changed.TLSConfig = config.TLSConfig.Clone()
		if control == "wrong CA" {
			changed.TLSConfig.RootCAs = x509.NewCertPool()
		} else {
			changed.TLSConfig.ServerName = "wrong-name.invalid"
		}
		_, failed, err := openConfig(ctx, changed)
		if failed != nil {
			failed.Close()
		}
		if err == nil {
			t.Fatal(control, "unexpectedly connected")
		}
		message := err.Error()
		if control == "wrong CA" && !strings.Contains(message, "unknown authority") {
			t.Fatal("wrong CA did not fail specifically", err)
		}
		if control == "wrong hostname" && !strings.Contains(message, "not wrong-name.invalid") {
			t.Fatal("wrong hostname did not fail specifically", err)
		}
		fmt.Println("Actual GORM/pgx connection rejected", control, "for certificate verification reason.")
	}
}
func TestCloudCoherentGraphSnapshot(t *testing.T) {
	cloud(t)
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()
	db, pool, err := Open(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	project := os.Getenv("PROBE_PROJECT_ID")
	if _, err = UUID(project); err != nil {
		t.Fatal("set PROBE_PROJECT_ID to dedicated owner-created fixture")
	}
	paused := make(chan struct{})
	release := make(chan struct{})
	var once atomic.Bool
	var readerPID atomic.Int64
	err = db.Callback().Query().After("gorm:query").Register("acceptance:pause_project", func(tx *gorm.DB) {
		if tx.Statement.Table == "projects" && once.CompareAndSwap(false, true) {
			var pid int64
			if err := tx.Statement.ConnPool.QueryRowContext(ctx, "SELECT pg_backend_pid()").Scan(&pid); err != nil {
				t.Error(err)
			}
			readerPID.Store(pid)
			close(paused)
			select {
			case <-release:
			case <-ctx.Done():
			}
		}
	})
	if err != nil {
		t.Fatal(err)
	}
	type outcome struct {
		snapshot Snapshot
		err      error
	}
	read := make(chan outcome, 1)
	go func() {
		snapshot, err := (Store{DB: db}).Snapshot(ctx, "10000000-0000-4000-8000-000000000001", project)
		read <- outcome{snapshot, err}
	}()
	select {
	case <-paused:
	case <-ctx.Done():
		t.Fatal("project SELECT was not paused")
	}
	write := make(chan error, 1)
	go func() {
		request, err := http.NewRequestWithContext(ctx, "POST", "http://127.0.0.1:8090/api/projects/"+project+"/tasks", strings.NewReader(`{"title":"Coherent writer"}`))
		if err != nil {
			write <- err
			return
		}
		request.Header.Set("Authorization", "Bearer "+os.Getenv("TASKS_NORTH_TOKEN"))
		request.Header.Set("Content-Type", "application/json")
		response, err := http.DefaultClient.Do(request)
		if err != nil {
			write <- err
			return
		}
		defer response.Body.Close()
		if response.StatusCode != 201 {
			write <- fmt.Errorf("writer status %d", response.StatusCode)
			return
		}
		write <- nil
	}()
	deadline := time.Now().Add(8 * time.Second)
	observed := false
	for time.Now().Before(deadline) {
		var count int
		err = db.Raw("SELECT count(DISTINCT pid) FROM pg_locks WHERE NOT granted AND ? = ANY(pg_blocking_pids(pid))", readerPID.Load()).Scan(&count).Error
		if err != nil {
			t.Fatal(err)
		}
		if count > 0 {
			observed = true
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	close(release)
	result := <-read
	if !observed {
		t.Fatal("actual HTTP writer was not observed waiting")
	}
	if result.err != nil {
		t.Fatal(result.err)
	}
	if len(result.snapshot.Tasks) != 0 || result.snapshot.Project.Revision != 0 {
		t.Fatal("reader mixed project/header with later task write")
	}
	if err = <-write; err != nil {
		t.Fatal(err)
	}
	if err = db.Callback().Query().Remove("acceptance:pause_project"); err != nil {
		t.Fatal(err)
	}
	after, err := (Store{DB: db}).Snapshot(ctx, "10000000-0000-4000-8000-000000000001", project)
	if err != nil || after.Project.Revision != 1 || len(after.Tasks) != 1 {
		t.Fatal("writer not visible in later complete snapshot", err)
	}
	encoded, _ := json.Marshal(after)
	fmt.Println("Observed SHARE snapshot blocked independent HTTP writer; old header/graph agree, later header/graph agree:", string(encoded))
}
