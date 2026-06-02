# clickhousectl Examples

Examples that use [`clickhousectl`](https://github.com/ClickHouse/clickhousectl) — the
ClickHouse command-line control plane for managing local and Cloud services —
to build agentic workflows around ClickHouse.

## Cloning the repository

If you want to run these examples locally, you'll need to first clone the repository:

```
git clone https://github.com/ClickHouse/examples.git
cd examples/ai/clickhousectl
```

## Examples

| Example | Description |
|---------|-------------|
| [Agentic SLA-breach detection and scaling](agentic-sla-scaling/README.md) | An AI agent that defends a query-latency SLA on ClickHouse Cloud: manufacture load, watch the SLA breach, then hand the breach to an agent that investigates the live system and applies the right scaling action — horizontal or vertical — on its own. |
