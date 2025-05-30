<div align="center">
<p>
<img src="https://github.com/ClickHouse/clickhouse-js/blob/a332672bfb70d54dfd27ae1f8f5169a6ffeea780/.static/logo.svg" width="200px" align="center">
</p>
<h1>ClickHouse Examples</h1>
</div>

![GitHub License](https://img.shields.io/github/license/ClickHouse/examples)

![Community Slack](https://img.shields.io/badge/Community_Slack-blue?style=social&logo=slack&logoColor=yellow&link=https%3A%2F%2Fclickhouse.com%2Fslack)
![Twitter Follow](https://img.shields.io/twitter/follow/ClickHouseDB)
![YouTube Channel](https://img.shields.io/youtube/channel/subscribers/UChtmrD-dsdpspr42P_PyRAw?label=YouTube)






This repository contains a collection of examples and recipes for ClickHouse.

Examples cover a range of topics, from ClickHouse internals to integrating with third parties, and will help anyone from novice to expert.

## Repo contents

- [blog-examples](./blog-examples/): Resources that support the [ClickHouse Blog](clickhouse.com/blog).
- [docker-compose-recipes](./docker-compose-recipes/README.md): Various docker compose recipes for spinning up ClickHouse and common integrations, like Kafka, Grafana, Dagster and more.
- [ethereum](./ethereum/README.md): Examples for working with Ethereum blockchain data, including table schemas, batch and streaming load examples, and various queries.
- [learn-clickhouse-with-mark](./learn-clickhouse-with-mark/README.md): A collection of resources for learning ClickHouse from Mark Needham.

## Contributing

Anyone is welcome to contribute to this repository by submitting a PR!

New contributors will need to sign the CLA when submitting their first PR.

If there's an example you'd love to see, feel free to open an issue to request it (or submit a PR!).

### Standards & conventions

- All examples should be self-contained, including documentation to use the example without relying on external resources (i.e., include a full README.md in the repo and do not just link to an external article).
- Directories and files should use kebab-case.

### ClickHouse employees

The [blog-examples](./blog-examples/) directory contains resources that support the [ClickHouse Blog](clickhouse.com/blog). If you are writing a blog post and want to store resources in this repo, add a new directory here and follow the same standards and conventions as other examples in this repo.