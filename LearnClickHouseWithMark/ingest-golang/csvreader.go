package main

import (
	"encoding/csv"
	"io"
	"log"
	"os"
)

func readCSVToChannel(filePath string, rowChan chan<- []string) {
	csvFile, err := os.Open(filePath)
	if err != nil {
		log.Fatal(err)
	}
	defer csvFile.Close()

	csvReader := csv.NewReader(csvFile)

	defer close(rowChan)

	if _, err := csvReader.Read(); err != nil { // Skip header or handle error
		log.Fatal(err)
	}

	for {
		record, err := csvReader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			log.Fatal(err)
		}
		rowChan <- record
	}
}
