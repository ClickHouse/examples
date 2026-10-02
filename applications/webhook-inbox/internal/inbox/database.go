package inbox

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func PoolConfig(user, password string) (*pgxpool.Config, error) {
	for _, key := range []string{"PGHOST", "PGDATABASE", "PGSSLROOTCERT"} {
		if os.Getenv(key) == "" {
			return nil, fmt.Errorf("missing %s", key)
		}
	}
	if user == "" {
		user = os.Getenv("PGUSER")
	}
	if password == "" {
		password = os.Getenv("PGPASSWORD")
	}
	if user == "" || password == "" {
		return nil, fmt.Errorf("database login is required")
	}
	port, err := strconv.ParseUint(envDefault("PGPORT", "5432"), 10, 16)
	if err != nil || port == 0 {
		return nil, fmt.Errorf("invalid PGPORT")
	}
	ca, err := os.ReadFile(os.Getenv("PGSSLROOTCERT"))
	if err != nil {
		return nil, fmt.Errorf("read Cloud CA: %w", err)
	}
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(ca) {
		return nil, fmt.Errorf("Cloud CA is not PEM")
	}
	cfg, err := pgxpool.ParseConfig("")
	if err != nil {
		return nil, fmt.Errorf("invalid database configuration")
	}
	cfg.ConnConfig.Host, cfg.ConnConfig.Port = os.Getenv("PGHOST"), uint16(port)
	cfg.ConnConfig.Database, cfg.ConnConfig.User, cfg.ConnConfig.Password = os.Getenv("PGDATABASE"), user, password
	cfg.ConnConfig.TLSConfig = &tls.Config{RootCAs: roots, ServerName: cfg.ConnConfig.Host, MinVersion: tls.VersionTLS12}
	cfg.ConnConfig.Fallbacks = nil // Never fall back to a plaintext connection.
	cfg.ConnConfig.ConnectTimeout = 10 * time.Second
	cfg.ConnConfig.RuntimeParams["statement_timeout"] = "5000"
	cfg.ConnConfig.RuntimeParams["application_name"] = "webhook-inbox"
	if user == "webhook_migrator" {
		cfg.ConnConfig.RuntimeParams["role"] = "webhook_owner"
	}
	cfg.MaxConns, cfg.MinConns = 5, 0
	return cfg, nil
}

func OpenPool(ctx context.Context, user, password string) (*pgxpool.Pool, error) {
	cfg, err := PoolConfig(user, password)
	if err != nil {
		return nil, err
	}
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, err
	}
	if err = pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("database connection failed")
	}
	return pool, nil
}
func envDefault(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
