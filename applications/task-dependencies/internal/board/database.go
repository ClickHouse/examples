package board

import (
	"context"
	"database/sql"
	"errors"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/stdlib"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
	"os"
	"time"
)

func Open(ctx context.Context) (*gorm.DB, *sql.DB, error) {
	if os.Getenv("PGSSLMODE") != "verify-full" || os.Getenv("PGSSLROOTCERT") == "" {
		return nil, nil, errors.New("PGSSLMODE=verify-full and official PGSSLROOTCERT are required")
	}
	config, err := pgx.ParseConfig("")
	if err != nil {
		return nil, nil, err
	}
	config.ConnectTimeout = 5 * time.Second
	config.RuntimeParams["application_name"] = "task-dependencies"
	config.RuntimeParams["statement_timeout"] = "10000"
	config.RuntimeParams["lock_timeout"] = "5000"
	config.RuntimeParams["idle_in_transaction_session_timeout"] = "15000"
	return openConfig(ctx, config)
}

func openConfig(ctx context.Context, config *pgx.ConnConfig) (*gorm.DB, *sql.DB, error) {
	pool := stdlib.OpenDB(*config)
	pool.SetMaxOpenConns(4)
	pool.SetMaxIdleConns(4)
	pool.SetConnMaxIdleTime(30 * time.Second)
	pool.SetConnMaxLifetime(15 * time.Minute)
	db, err := gorm.Open(postgres.New(postgres.Config{Conn: pool}), &gorm.Config{Logger: logger.Default.LogMode(logger.Silent), DisableAutomaticPing: true, SkipDefaultTransaction: true})
	if err != nil {
		pool.Close()
		return nil, nil, err
	}
	if err = pool.PingContext(ctx); err != nil {
		pool.Close()
		return nil, nil, err
	}
	return db, pool, nil
}
