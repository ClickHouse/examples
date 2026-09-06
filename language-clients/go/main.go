// Client tour: github.com/ClickHouse/clickhouse-go/v2, native API, native TCP+TLS
// protocol. Every step below is documented in the parent README.
package main

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/ClickHouse/clickhouse-go/v2"
	"github.com/google/uuid"
)

const (
	totalRows = 10_000
	batchSize = 1_000
)

// Reading maps one row of client_tour.readings_go. `ch` tags are required because
// the driver matches struct fields to column names exactly (case sensitive), and
// our columns are snake_case while Go fields must be exported.
type Reading struct {
	ReadingID   uuid.UUID         `ch:"reading_id"`
	RecordedAt  time.Time         `ch:"recorded_at"`
	DeviceID    string            `ch:"device_id"`
	Site        string            `ch:"site"`
	TempC       float64           `ch:"temp_c"`
	HumidityPct *float64          `ch:"humidity_pct"` // nil -> Nullable(Float64) NULL
	BatteryPct  uint8             `ch:"battery_pct"`
	Tags        []string          `ch:"tags"`
	Attributes  map[string]string `ch:"attributes"`
}

// SiteSummary maps one row of the step 6 aggregate query.
type SiteSummary struct {
	Site     string  `ch:"site"`
	Readings uint64  `ch:"readings"`
	AvgTempC float64 `ch:"avg_temp_c"`
	MaxTempC float64 `ch:"max_temp_c"`
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run() error {
	database, err := requiredEnv("CLICKHOUSE_DATABASE")
	if err != nil {
		return err
	}
	table := database + ".readings_go"

	conn, err := connect()
	if err != nil {
		return err
	}
	defer conn.Close()

	ctx := context.Background()

	if err := step1Connect(ctx, conn); err != nil {
		return err
	}
	if err := step2CreateTable(ctx, conn, table); err != nil {
		return err
	}
	if err := step3Insert(ctx, conn, table); err != nil {
		return err
	}
	if err := step4ParameterizedQuery(ctx, conn, table); err != nil {
		return err
	}
	if err := step5Stream(ctx, conn, table); err != nil {
		return err
	}
	if err := step6Aggregate(ctx, conn, table); err != nil {
		return err
	}
	if err := step7Error(ctx, conn, database); err != nil {
		return err
	}
	return nil
}

// connect opens a native-protocol connection to ClickHouse Cloud over TLS.
// An empty tls.Config uses the system trust store, which is all Cloud's
// certificates need.
func connect() (clickhouse.Conn, error) {
	host, err := requiredEnv("CLICKHOUSE_HOST")
	if err != nil {
		return nil, err
	}
	port, err := requiredEnv("CLICKHOUSE_NATIVE_PORT")
	if err != nil {
		return nil, err
	}
	user, err := requiredEnv("CLICKHOUSE_USER")
	if err != nil {
		return nil, err
	}
	password, err := requiredEnv("CLICKHOUSE_PASSWORD")
	if err != nil {
		return nil, err
	}
	database, err := requiredEnv("CLICKHOUSE_DATABASE")
	if err != nil {
		return nil, err
	}

	return clickhouse.Open(&clickhouse.Options{
		Addr: []string{fmt.Sprintf("%s:%s", host, port)},
		Auth: clickhouse.Auth{
			Database: database,
			Username: user,
			Password: password,
		},
		TLS: &tls.Config{},
	})
}

func requiredEnv(name string) (string, error) {
	if v := os.Getenv(name); v != "" {
		return v, nil
	}
	return "", fmt.Errorf("missing required environment variable %s", name)
}

// step1Connect pings the server with a real query rather than relying on the
// handshake alone, and reports the version the SQL layer reports.
func step1Connect(ctx context.Context, conn clickhouse.Conn) error {
	var version string
	if err := conn.QueryRow(ctx, "SELECT version()").Scan(&version); err != nil {
		return err
	}
	fmt.Printf("1 connect: ok, server version %s\n", version)
	return nil
}

func step2CreateTable(ctx context.Context, conn clickhouse.Conn, table string) error {
	if err := conn.Exec(ctx, "DROP TABLE IF EXISTS "+table); err != nil {
		return err
	}
	ddl := fmt.Sprintf(`
		CREATE TABLE %s
		(
			reading_id   UUID,
			recorded_at  DateTime64(3, 'UTC'),
			device_id    LowCardinality(String),
			site         LowCardinality(String),
			temp_c       Float64,
			humidity_pct Nullable(Float64),
			battery_pct  UInt8,
			tags         Array(String),
			attributes   Map(String, String)
		)
		ENGINE = MergeTree
		ORDER BY (site, device_id, recorded_at)
	`, table)
	if err := conn.Exec(ctx, ddl); err != nil {
		return err
	}
	fmt.Println("2 create table: ok")
	return nil
}

// step3Insert generates the 10,000 rows from their index and sends them as ten
// PrepareBatch/AppendStruct/Send round trips. AppendStruct serializes straight
// to the native column format, no SQL literals involved.
func step3Insert(ctx context.Context, conn clickhouse.Conn, table string) error {
	sites := []string{"amsterdam", "berlin", "london", "madrid", "paris"}
	epoch := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)

	batches := 0
	for offset := 0; offset < totalRows; offset += batchSize {
		batch, err := conn.PrepareBatch(ctx, "INSERT INTO "+table)
		if err != nil {
			return err
		}
		for i := offset; i < offset+batchSize; i++ {
			i64 := int64(i)

			var humidityPct *float64
			if i%10 != 0 {
				h := 30.0 + float64((i64*104729)%6000)/100.0
				humidityPct = &h
			}

			var tags []string
			switch i % 3 {
			case 0:
				tags = []string{"calibrated"}
			case 1:
				tags = []string{"calibrated", "outdoor"}
			default:
				tags = []string{}
			}

			model := "tx-200"
			if i%2 == 0 {
				model = "tx-100"
			}

			reading := Reading{
				ReadingID:   uuid.MustParse(fmt.Sprintf("00000000-0000-4000-8000-%012x", i)),
				RecordedAt:  epoch.Add(time.Duration(i64*1000+(i64*37)%1000) * time.Millisecond),
				DeviceID:    fmt.Sprintf("device-%02d", i%50),
				Site:        sites[(i%50)%5],
				TempC:       15.0 + float64((i64*7919)%1997)/100.0,
				HumidityPct: humidityPct,
				BatteryPct:  uint8(100 - i%101),
				Tags:        tags,
				Attributes: map[string]string{
					"firmware": fmt.Sprintf("1.%d", i%4),
					"model":    model,
				},
			}
			if err := batch.AppendStruct(&reading); err != nil {
				return err
			}
		}
		if err := batch.Send(); err != nil {
			return err
		}
		batches++
	}
	fmt.Printf("3 insert: %d rows in %d batches\n", totalRows, batches)
	return nil
}

// step4ParameterizedQuery binds both values server-side via clickhouse.WithParameters,
// which substitutes {name:Type} placeholders on the server rather than the client.
func step4ParameterizedQuery(ctx context.Context, conn clickhouse.Conn, table string) error {
	paramCtx := clickhouse.Context(ctx, clickhouse.WithParameters(clickhouse.Parameters{
		"device":   "device-07",
		"min_temp": "30.0",
	}))
	query := fmt.Sprintf(
		"SELECT count() FROM %s WHERE device_id = {device:String} AND temp_c > {min_temp:Float64}",
		table,
	)
	var count uint64
	if err := conn.QueryRow(paramCtx, query).Scan(&count); err != nil {
		return err
	}
	fmt.Printf("4 parameterized query: %d readings for device-07 above 30.0 C\n", count)
	return nil
}

// step5Stream reads every row through the driver's row-by-row cursor: conn.Query
// opens the result stream and rows.Next/Scan pulls one row at a time off the
// wire, so the full result set is never buffered client-side.
func step5Stream(ctx context.Context, conn clickhouse.Conn, table string) error {
	rows, err := conn.Query(ctx, "SELECT * FROM "+table+" ORDER BY recorded_at")
	if err != nil {
		return err
	}
	defer rows.Close()

	var (
		rowCount      int
		batteryTotal  int64
		humidityNulls int
		tagCount      int
	)
	for rows.Next() {
		var (
			readingID   uuid.UUID
			recordedAt  time.Time
			deviceID    string
			site        string
			tempC       float64
			humidityPct *float64
			batteryPct  uint8
			tags        []string
			attributes  map[string]string
		)
		if err := rows.Scan(
			&readingID, &recordedAt, &deviceID, &site, &tempC,
			&humidityPct, &batteryPct, &tags, &attributes,
		); err != nil {
			return err
		}
		rowCount++
		batteryTotal += int64(batteryPct)
		if humidityPct == nil {
			humidityNulls++
		}
		tagCount += len(tags)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	fmt.Printf(
		"5 stream: %d rows, battery total %d, humidity null in %d rows, %d tags\n",
		rowCount, batteryTotal, humidityNulls, tagCount,
	)
	return nil
}

// step6Aggregate scans each result row straight into a typed SiteSummary via
// ScanStruct, using the same ch-tag field mapping as AppendStruct.
func step6Aggregate(ctx context.Context, conn clickhouse.Conn, table string) error {
	query := fmt.Sprintf(`
		SELECT site, count() AS readings,
		       round(avg(temp_c), 2) AS avg_temp_c,
		       round(max(temp_c), 2) AS max_temp_c
		FROM %s
		GROUP BY site ORDER BY site
	`, table)
	rows, err := conn.Query(ctx, query)
	if err != nil {
		return err
	}
	defer rows.Close()

	fmt.Println("6 aggregate: site readings avg_temp_c max_temp_c")
	for rows.Next() {
		var s SiteSummary
		if err := rows.ScanStruct(&s); err != nil {
			return err
		}
		fmt.Printf("6 aggregate: %s %d %.2f %.2f\n", s.Site, s.Readings, s.AvgTempC, s.MaxTempC)
	}
	return rows.Err()
}

// step7Error queries a table that does not exist and unwraps the driver's
// *clickhouse.Exception to read the server's numeric error code.
func step7Error(ctx context.Context, conn clickhouse.Conn, database string) error {
	_, err := conn.Query(ctx, "SELECT count() FROM "+database+".no_such_table_go")
	var chErr *clickhouse.Exception
	if !errors.As(err, &chErr) {
		return fmt.Errorf("expected *clickhouse.Exception, got: %w", err)
	}
	fmt.Printf("7 error: server error code %d\n", chErr.Code)
	return nil
}
