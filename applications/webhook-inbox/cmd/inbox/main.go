package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/ClickHouse/examples/applications/webhook-inbox/internal/inbox"
)

func main() {
	if err := run(); err != nil {
		log.Print("Inbox command failed; check configuration, role, CA and database readiness")
		os.Exit(1)
	}
}
func run() error {
	if len(os.Args) != 2 {
		return fmt.Errorf("usage: inbox serve|worker|worker-once|migrate|migrate-down|seed")
	}
	mode := os.Args[1]
	roles := map[string]string{"serve": "webhook_receiver", "worker": "webhook_worker", "worker-once": "webhook_worker", "migrate": "webhook_migrator", "migrate-down": "webhook_migrator", "seed": "webhook_migrator"}
	if roles[mode] == "" || os.Getenv("PGUSER") != roles[mode] {
		return fmt.Errorf("use the role for this command")
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	pool, err := inbox.OpenPool(ctx, "", "")
	if err != nil {
		return err
	}
	defer pool.Close()
	switch mode {
	case "migrate", "migrate-down":
		return inbox.Migrate(ctx, pool, mode == "migrate-down")
	case "seed":
		return inbox.Seed(ctx, pool)
	case "worker-once":
		worked, err := (inbox.Worker{Pool: pool}).ProcessOne(ctx)
		if err == nil {
			fmt.Printf("worked=%t\n", worked)
		}
		return err
	case "worker":
		worker := inbox.Worker{Pool: pool}
		for ctx.Err() == nil {
			worked, err := worker.ProcessOne(ctx)
			if err != nil && ctx.Err() == nil {
				log.Print("Worker transaction failed; next poll will retry")
			}
			if !worked || err != nil {
				select {
				case <-ctx.Done():
				case <-time.After(500 * time.Millisecond):
				}
			}
		}
		return nil
	case "serve":
		tokens, err := inbox.ParseTokens(os.Getenv("INTEGRATION_TOKENS"))
		if err != nil {
			return err
		}
		api, err := inbox.NewAPI(ctx, pool, tokens)
		if err != nil {
			return err
		}
		port := os.Getenv("PORT")
		if port == "" {
			port = "3000"
		}
		n, err := strconv.Atoi(port)
		if err != nil || n < 1 || n > 65535 {
			return fmt.Errorf("invalid PORT")
		}
		server := &http.Server{Addr: "127.0.0.1:" + port, Handler: api.Handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 8192}
		listener, err := net.Listen("tcp", server.Addr)
		if err != nil {
			return err
		}
		errors := make(chan error, 1)
		go func() { errors <- server.Serve(listener) }()
		log.Printf("Webhook inbox listening on http://%s", server.Addr)
		select {
		case err := <-errors:
			if err != http.ErrServerClosed {
				return err
			}
		case <-ctx.Done():
			shutdown, stop := context.WithTimeout(context.Background(), 5*time.Second)
			defer stop()
			return server.Shutdown(shutdown)
		}
	}
	return nil
}
