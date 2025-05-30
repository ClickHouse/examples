# Ethereum batch examples

This directory contains examples that demonstrate how to work with the Ethereum dataset in a batch style.

## Schemas

The [schemas](schemas) directory contains the ClickHouse schemas for the Ethereum data.

## Beam (Dataflow)

The [beam_dataflow](beam_dataflow) directory contains an example of a batch Apache Beam (GCP Dataflow) job to move Ethereum data from BigQuery to ClickHouse.


## Files in blob storage

The [inserts](inserts) directory contains example `INSERT INTO` statements that can be executed on ClickHouse to load data directly from files in blob storage.