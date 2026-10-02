package main

import (
	"bytes"
	"context"
	"crypto/subtle"
	"database/sql"
	"database/sql/driver"
	"entgo.io/contrib/entgql"
	"errors"
	"example.com/playlist-api/ent"
	"example.com/playlist-api/graph"
	"example.com/playlist-api/internal/app"
	"github.com/99designs/gqlgen/graphql"
	"github.com/99designs/gqlgen/graphql/handler"
	"github.com/99designs/gqlgen/graphql/handler/extension"
	"github.com/99designs/gqlgen/graphql/handler/transport"
	"github.com/google/uuid"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"regexp"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"
)

func main() {
	if err := run(); err != nil {
		log.Fatal("Playlist API startup failed.")
	}
}
func run() error {
	tokens := []string{os.Getenv("ACCOUNT_A_TOKEN"), os.Getenv("ACCOUNT_B_TOKEN")}
	pattern := regexp.MustCompile(`^[A-Za-z0-9_-]{32,128}$`)
	if !pattern.MatchString(tokens[0]) || !pattern.MatchString(tokens[1]) || tokens[0] == tokens[1] {
		return errors.New("distinct tokens required")
	}
	owners := []uuid.UUID{uuid.MustParse("00000000-0000-4000-8000-000000000001"), uuid.MustParse("00000000-0000-4000-8000-000000000002")}
	client, _, err := app.Open()
	if err != nil {
		return err
	}
	defer client.Close()
	cfg := graph.Config{Resolvers: &graph.Resolver{}}
	cfg.Complexity.Query.Playlists = func(child, limit int, cursor *string) int {
		if limit < 1 || limit > 10 {
			return app.CostLimit + 1
		}
		return app.Cost(child, limit)
	}
	cfg.Complexity.Query.Tracks = func(child, limit int) int { return app.Cost(child, limit) }
	cfg.Complexity.Playlist.Items = func(child int) int { return app.Cost(child, 50) }
	server := handler.New(graph.NewExecutableSchema(cfg))
	server.AddTransport(transport.POST{})
	server.SetErrorPresenter(app.PresentError)
	server.SetRecoverFunc(func(context.Context, any) error { return errors.New("request failed") })
	server.Use(app.Policy{})
	server.Use(extension.FixedComplexityLimit(app.CostLimit))
	server.AroundResponses(func(ctx context.Context, next graphql.ResponseHandler) *graphql.Response {
		response := app.Sanitize(ctx, next)
		if os.Getenv("QUERY_COUNT_EVIDENCE") == "1" && response != nil {
			response.Extensions = map[string]any{"sqlStatements": app.SQLCount(ctx)}
		}
		return response
	})
	server.Use(app.QuerySnapshot{Client: client})
	server.Use(entgql.Transactioner{TxOpener: entgql.TxOpenerFunc(func(ctx context.Context) (context.Context, driver.Tx, error) {
		tx, err := client.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
		if err != nil {
			return nil, nil, errors.New("Database unavailable.")
		}
		ctx = ent.NewTxContext(ctx, tx)
		ctx = ent.NewContext(ctx, tx.Client())
		return ctx, tx, nil
	})})
	api := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/query" {
			http.NotFound(w, r)
			return
		}
		if r.Method != "POST" {
			w.WriteHeader(405)
			return
		}
		headers := r.Header.Values("Authorization")
		owner := uuid.Nil
		if len(headers) == 1 && strings.HasPrefix(headers[0], "Bearer ") {
			value := strings.TrimPrefix(headers[0], "Bearer ")
			if len(value) <= 128 {
				for i, token := range tokens {
					if subtle.ConstantTimeCompare([]byte(value), []byte(token)) == 1 {
						owner = owners[i]
					}
				}
			}
		}
		if owner == uuid.Nil {
			w.WriteHeader(401)
			return
		}
		r.Body = http.MaxBytesReader(w, r.Body, 16384)
		data, err := io.ReadAll(r.Body)
		if err != nil {
			w.WriteHeader(413)
			return
		}
		if !utf8.Valid(data) {
			w.WriteHeader(400)
			return
		}
		r.Body = io.NopCloser(bytes.NewReader(data))
		ctx := app.WithOwner(r.Context(), owner)
		ctx, count := app.WithCounter(ctx)
		if os.Getenv("QUERY_COUNT_EVIDENCE") == "1" {
			defer func() { log.Printf("Observed Ent SQL statements=%d", count.Load()) }()
		}
		server.ServeHTTP(w, r.WithContext(ctx))
	})
	httpServer := &http.Server{Addr: "127.0.0.1:8080", Handler: http.TimeoutHandler(api, 25*time.Second, "Request timed out."), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 8192}
	stop := make(chan os.Signal, 1)
	shutdownDone := make(chan error, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-stop
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		shutdownDone <- httpServer.Shutdown(ctx)
	}()
	err = httpServer.ListenAndServe()
	if errors.Is(err, http.ErrServerClosed) {
		return <-shutdownDone
	}
	return err
}
