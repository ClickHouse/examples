package inbox

import (
	"bytes"
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/ClickHouse/examples/applications/webhook-inbox/internal/store"
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Payload struct {
	Kind string `json:"kind"`
	Path string `json:"path"`
}

func ParsePayload(raw []byte) (Payload, error) {
	var payload Payload
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&payload); err != nil {
		return payload, fmt.Errorf("invalid payload")
	}
	var extra any
	if decoder.Decode(&extra) != io.EOF {
		return payload, fmt.Errorf("expected one JSON object")
	}
	if payload.Kind != "page_view" && payload.Kind != "demo_failure" {
		return payload, fmt.Errorf("unsupported kind")
	}
	if len(payload.Path) == 0 || len(payload.Path) > 256 || !strings.HasPrefix(payload.Path, "/") || strings.ContainsAny(payload.Path, "\r\n\x00") {
		return payload, fmt.Errorf("path must be 1-256 bytes and start with /")
	}
	return payload, nil
}

type tokenIdentity struct {
	hash [32]byte
	id   pgtype.UUID
}
type Tokens []tokenIdentity

func ParseTokens(raw string) (Tokens, error) {
	var values map[string]string
	if err := json.Unmarshal([]byte(raw), &values); err != nil || len(values) == 0 || len(values) > 20 {
		return nil, fmt.Errorf("INTEGRATION_TOKENS must map integration UUIDs to tokens")
	}
	tokens := Tokens{}
	seen := map[string]bool{}
	for id, token := range values {
		var uuid pgtype.UUID
		if err := uuid.Scan(id); err != nil || !uuid.Valid || len(token) < 32 || len(token) > 256 || seen[token] || strings.ContainsAny(token, " \t\r\n") {
			return nil, fmt.Errorf("invalid integration ID, token or duplicate token")
		}
		seen[token] = true
		tokens = append(tokens, tokenIdentity{hash: sha256.Sum256([]byte(token)), id: uuid})
	}
	return tokens, nil
}

type identityKey struct{}

func identity(ctx context.Context) pgtype.UUID { return ctx.Value(identityKey{}).(pgtype.UUID) }
func (tokens Tokens) authenticate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		if !strings.HasPrefix(header, "Bearer ") || len(header) > 263 {
			writeError(w, 401, "Invalid token")
			return
		}
		hash := sha256.Sum256([]byte(strings.TrimPrefix(header, "Bearer ")))
		var id pgtype.UUID
		for _, token := range tokens {
			if subtle.ConstantTimeCompare(hash[:], token.hash[:]) == 1 {
				id = token.id
			}
		}
		if !id.Valid {
			writeError(w, 401, "Invalid token")
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), identityKey{}, id)))
	})
}

var eventIDPattern = regexp.MustCompile(`^[A-Za-z0-9_.-]{1,80}$`)

type API struct {
	pool    *pgxpool.Pool
	queries *store.Queries
	tokens  Tokens
}

func NewAPI(ctx context.Context, pool *pgxpool.Pool, tokens Tokens) (*API, error) {
	queries := store.New(pool)
	for _, token := range tokens {
		exists, err := queries.IntegrationExists(ctx, token.id)
		if err != nil || !exists {
			return nil, fmt.Errorf("configured integration is not seeded")
		}
	}
	return &API{pool: pool, queries: queries, tokens: tokens}, nil
}
func (api *API) Handler() http.Handler {
	router := chi.NewRouter()
	router.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
		defer cancel()
		if api.pool.Ping(ctx) != nil {
			writeError(w, 503, "Database unavailable")
			return
		}
		writeJSON(w, 200, map[string]string{"status": "ok"})
	})
	router.Group(func(r chi.Router) {
		r.Use(api.tokens.authenticate)
		r.Post("/events", api.receive)
		r.Get("/events/{externalID}", api.inspect)
		r.Get("/stats", api.stats)
	})
	return router
}
func (api *API) receive(w http.ResponseWriter, r *http.Request) {
	externalID := r.Header.Get("X-Event-ID")
	if !eventIDPattern.MatchString(externalID) {
		writeError(w, 400, "X-Event-ID must be 1-80 ASCII letters, digits, _, . or -")
		return
	}
	if strings.Split(r.Header.Get("Content-Type"), ";")[0] != "application/json" {
		writeError(w, 415, "Use application/json")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 4096)
	raw, err := io.ReadAll(r.Body)
	if err != nil {
		var limit *http.MaxBytesError
		if errors.As(err, &limit) {
			writeError(w, 413, "Body exceeds 4096 bytes")
		} else {
			writeError(w, 400, "Invalid body")
		}
		return
	}
	if _, err = ParsePayload(raw); err != nil {
		writeError(w, 400, err.Error())
		return
	}
	digest := sha256.Sum256(raw)
	hash := hex.EncodeToString(digest[:])
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	event, err := api.queries.InsertEvent(ctx, store.InsertEventParams{IntegrationID: identity(ctx), ExternalEventID: externalID, Payload: raw, PayloadSha256: hash})
	replay := false
	if errors.Is(err, pgx.ErrNoRows) {
		// The unique-key conflict waits for its writer, then this separate READ
		// COMMITTED statement can see the accepted row.
		event, err = api.queries.GetEvent(ctx, store.GetEventParams{IntegrationID: identity(ctx), ExternalEventID: externalID})
		replay = true
	}
	if err != nil {
		writeError(w, 503, "Inbox unavailable; retry with the same ID and bytes")
		return
	}
	if event.PayloadSha256 != hash {
		writeError(w, 409, "Event ID already has a different payload")
		return
	}
	writeJSON(w, 202, map[string]any{"event": eventDTO(event), "replayed": replay})
}
func (api *API) inspect(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "externalID")
	if !eventIDPattern.MatchString(id) {
		writeError(w, 400, "Invalid event ID")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	event, err := api.queries.GetEvent(ctx, store.GetEventParams{IntegrationID: identity(ctx), ExternalEventID: id})
	if errors.Is(err, pgx.ErrNoRows) {
		writeError(w, 404, "Event not found")
		return
	}
	if err != nil {
		writeError(w, 503, "Inbox unavailable")
		return
	}
	writeJSON(w, 200, eventDTO(event))
}
func (api *API) stats(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	count, err := api.queries.GetCounter(ctx, identity(ctx))
	if err != nil {
		writeError(w, 503, "Inbox unavailable")
		return
	}
	writeJSON(w, 200, map[string]int64{"processed_events": count})
}
func eventDTO(event store.WebhookEvent) map[string]any {
	var processed any
	if event.ProcessedAt.Valid {
		processed = event.ProcessedAt.Time
	}
	var lastError any
	if event.LastError.Valid {
		lastError = event.LastError.String
	}
	return map[string]any{"id": event.ID, "external_event_id": event.ExternalEventID, "payload": json.RawMessage(event.Payload),
		"status": event.Status, "attempts": event.Attempts, "last_error": lastError, "created_at": event.CreatedAt.Time, "processed_at": processed}
}
func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}
