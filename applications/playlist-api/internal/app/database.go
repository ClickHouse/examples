package app

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"database/sql"
	"entgo.io/ent/dialect"
	entsql "entgo.io/ent/dialect/sql"
	"errors"
	"example.com/playlist-api/ent"
	"fmt"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/stdlib"
	"net"
	"net/url"
	"os"
	"sync/atomic"
	"time"
)

type counterKey struct{}

func WithCounter(ctx context.Context) (context.Context, *atomic.Int64) {
	count := &atomic.Int64{}
	return context.WithValue(ctx, counterKey{}, count), count
}
func counted(ctx context.Context) {
	if count, ok := ctx.Value(counterKey{}).(*atomic.Int64); ok {
		count.Add(1)
	}
}

type countedDriver struct{ dialect.Driver }

func (d countedDriver) Query(ctx context.Context, q string, args, v any) error {
	counted(ctx)
	return d.Driver.Query(ctx, q, args, v)
}
func (d countedDriver) Exec(ctx context.Context, q string, args, v any) error {
	counted(ctx)
	return d.Driver.Exec(ctx, q, args, v)
}
func (d countedDriver) Tx(ctx context.Context) (dialect.Tx, error) {
	tx, err := d.Driver.Tx(ctx)
	if err != nil {
		return nil, err
	}
	return countedTx{tx}, nil
}

// Ent BeginTx uses its optional dialect.TxBeginner interface; preserve it.
func (d countedDriver) BeginTx(ctx context.Context, options *sql.TxOptions) (dialect.Tx, error) {
	tx, err := d.Driver.(interface {
		BeginTx(context.Context, *sql.TxOptions) (dialect.Tx, error)
	}).BeginTx(ctx, options)
	if err != nil {
		return nil, err
	}
	return countedTx{tx}, nil
}

type countedTx struct{ dialect.Tx }

func (t countedTx) Query(ctx context.Context, q string, args, v any) error {
	counted(ctx)
	return t.Tx.Query(ctx, q, args, v)
}
func (t countedTx) Exec(ctx context.Context, q string, args, v any) error {
	counted(ctx)
	return t.Tx.Exec(ctx, q, args, v)
}
func Config() (*pgx.ConnConfig, error) {
	host := os.Getenv("PGHOST")
	if host == "" {
		return nil, errors.New("PGHOST required")
	}
	port := os.Getenv("PGPORT")
	if port == "" {
		port = "5432"
	}
	database := os.Getenv("PGDATABASE")
	if database == "" {
		database = "postgres"
	}
	u := url.URL{Scheme: "postgres", Host: net.JoinHostPort(host, port), Path: database, User: url.UserPassword(os.Getenv("PGUSER"), os.Getenv("PGPASSWORD"))}
	params := url.Values{"sslmode": {"verify-full"}, "sslrootcert": {os.Getenv("PGSSLROOTCERT")}, "connect_timeout": {"10"}, "application_name": {"playlist-api"}}
	u.RawQuery = params.Encode()
	config, err := pgx.ParseConfig(u.String())
	if err != nil {
		return nil, errors.New("Invalid database configuration")
	}
	ca, err := os.ReadFile(os.Getenv("PGSSLROOTCERT"))
	if err != nil {
		return nil, errors.New("Cloud CA required")
	}
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(ca) {
		return nil, errors.New("Cloud CA invalid")
	}
	config.TLSConfig = &tls.Config{RootCAs: roots, ServerName: host, MinVersion: tls.VersionTLS12}
	config.Fallbacks = nil
	config.RuntimeParams["search_path"] = "playlist_api,public"
	config.RuntimeParams["statement_timeout"] = "10000"
	config.RuntimeParams["lock_timeout"] = "8000"
	config.ConnectTimeout = 10 * time.Second
	return config, nil
}

func Open() (*ent.Client, *sql.DB, error) {
	config, err := Config()
	if err != nil {
		return nil, nil, err
	}
	db := stdlib.OpenDB(*config)
	db.SetMaxOpenConns(4)
	db.SetMaxIdleConns(2)
	db.SetConnMaxLifetime(15 * time.Minute)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err = db.PingContext(ctx); err != nil {
		db.Close()
		return nil, nil, fmt.Errorf("Database connection failed")
	}
	return ent.NewClient(ent.Driver(countedDriver{entsql.OpenDB(dialect.Postgres, db)})), db, nil
}

func SQLCount(ctx context.Context) int64 {
	if c, ok := ctx.Value(counterKey{}).(*atomic.Int64); ok {
		return c.Load()
	}
	return 0
}
