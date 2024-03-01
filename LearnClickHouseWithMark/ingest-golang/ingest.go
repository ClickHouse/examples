package main

import (
	"context"
	"flag"
	"fmt"
	"github.com/ClickHouse/clickhouse-go/v2"
	"github.com/ClickHouse/clickhouse-go/v2/lib/driver"
	"log"
	"strconv"
	"sync"
)

func main() {
	batchSize := flag.Int("batchSize", 10000, "Batch size")
	fileName := flag.String("fileName", "performance.csv", "File to ingest")
	numWorkers := flag.Int("numWorkers", 5, "# of concurrent workers")
	flag.Parse()

	rowChan := make(chan []string)
	go readCSVToChannel(*fileName, rowChan)

	conn, err := connectToClickHouse("localhost:9000")
	if err != nil {
		log.Fatal(err)
	}

	var wg sync.WaitGroup
	for i := 0; i < *numWorkers; i++ {
		wg.Add(1)
		go ingestRecords(&wg, rowChan, conn, *batchSize)
	}

	wg.Wait()
}

func connectToClickHouse(host string) (driver.Conn, error) {
	var (
		ctx       = context.Background()
		conn, err = clickhouse.Open(&clickhouse.Options{
			Addr: []string{host},
			Auth: clickhouse.Auth{
				Database: "default",
				Username: "default",
			},
		})
	)

	if err != nil {
		return nil, err
	}

	if err := conn.Ping(ctx); err != nil {
		if ex, ok := err.(*clickhouse.Exception); ok {
			fmt.Printf("Exception [%d] %s \n%s\n",
				ex.Code, ex.Message, ex.StackTrace)
		}
		return nil, err
	}
	return conn, nil
}

func ingestRecords(wg *sync.WaitGroup, rowChan <-chan []string,
	conn driver.Conn, batchSize int) {
	defer wg.Done()

	newBatch := func() driver.Batch {
		ctx := context.Background()
		batch, err := conn.PrepareBatch(ctx, `INSERT INTO performance (
			quadKey, tileWKT,  tileX, tileY, downloadSpeedKbps,  
			uploadSpeedKbps, latencyMs, downloadLatencyMs,  
			uploadLatencyMs, tests, devices)`,
		)
		if err != nil {
			panic(err)
		}
		return batch
	}
	batch := newBatch()
	recordsProcessed := 0
	for row := range rowChan {
		quadKey := row[0]
		tile := row[1]
		tileX, _ := strconv.ParseFloat(row[2], 32)
		tileY, _ := strconv.ParseFloat(row[3], 32)
		downloadSpeedKbps, _ := strconv.ParseUint(row[4], 10, 32)
		uploadSpeedKbps, _ := strconv.ParseUint(row[5], 10, 32)
		latencyMs, _ := strconv.ParseUint(row[6], 10, 32)
		downloadLatencyMs, _ := strconv.ParseUint(row[7], 10, 32)
		uploadLatencyMs, _ := strconv.ParseUint(row[8], 10, 32)
		tests, _ := strconv.ParseUint(row[9], 10, 32)
		devices, _ := strconv.ParseUint(row[10], 10, 16)

		err := batch.Append(
			quadKey, tile,
			tileX, tileY,
			downloadSpeedKbps, uploadSpeedKbps,
			latencyMs, downloadLatencyMs, uploadLatencyMs,
			tests, devices,
		)
		if err != nil {
			log.Fatal(err)
		}

		recordsProcessed++

		if recordsProcessed%batchSize == 0 {
			if err := batch.Send(); err != nil {
				log.Fatal(err)
			}
			batch = newBatch()
		}
	}

	if err := batch.Send(); err != nil {
		log.Fatal(err)
	}
}
