package main

import (
	"context"
	"errors"
	"github.com/ClickHouse/examples/applications/task-dependencies/internal/board"
	"github.com/ClickHouse/examples/applications/task-dependencies/internal/httpapi"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	credentials, err := httpapi.Credentials(os.Getenv("TASKS_NORTH_TOKEN"), os.Getenv("TASKS_SOUTH_TOKEN"))
	if err != nil {
		log.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	db, pool, err := board.Open(ctx)
	cancel()
	if err != nil {
		log.Fatal("Verified database connection failed; check private setup.")
	}
	defer pool.Close()
	var version int
	if err = db.Raw("SELECT version FROM task_dependencies.schema_migrations WHERE version = 1").Scan(&version).Error; err != nil || version != 1 {
		log.Fatal("Apply versioned migrations before startup.")
	}
	server := &http.Server{Addr: "127.0.0.1:8090", Handler: httpapi.Router(board.Store{DB: db}, credentials), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 15 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16384}
	stop, stopCancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stopCancel()
	joined := make(chan struct{})
	go func() {
		defer close(joined)
		<-stop.Done()
		shutdown, done := context.WithTimeout(context.Background(), 15*time.Second)
		defer done()
		if err := server.Shutdown(shutdown); err != nil {
			server.Close()
		}
	}()
	log.Print("Task dependency API listening on loopback port 8090.")
	if err = server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		stopCancel()
		<-joined
		log.Fatal("Local HTTP listener failed.")
	}
	<-joined
}
