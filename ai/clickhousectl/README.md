# clickhousectl Examples

Examples that use [`clickhousectl`](https://github.com/ClickHouse/clickhousectl), the ClickHouse CLI for managing local and Cloud services, to build agentic workflows around ClickHouse.

[Try ClickHouse Cloud](https://clickhouse.com/cloud) with $300 in credits for a 30-day trial. The scaling example below requires a Cloud service on a tier that supports scaling. For a local AI walkthrough, see the [MCP examples](../mcp/README.md).

## Cloning the repository

```bash
git clone https://github.com/ClickHouse/examples.git
cd examples/ai/clickhousectl
```

## Examples

| Example | Description |
|---------|-------------|
| [Agentic SLA-breach detection and scaling](agentic-sla-scaling/README.md) | Generate workload pressure on a dedicated ClickHouse Cloud service, measure dashboard query latency, and hand a current breach to an agent that investigates and can request one scaling action when justified. |
