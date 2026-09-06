"use client";
import { useState } from "react";
import { useAgentContext, useFrontendTool } from "@copilotkit/react-core/v2";
import { z } from "zod";
import GenericChart, { ChartProps } from "./GenericChart";

const chartSchema = z.object({
  data: z.array(z.record(z.string(), z.union([z.string(), z.number()]))),
  chartType: z.enum(["bar", "line", "area", "pie"]),
  title: z.string().max(30),
  xAxis: z.string(),
});

export default function ChartsGrid() {
  const [charts, setCharts] = useState<ChartProps[]>([]);
  useAgentContext({ description: "Charts currently displayed", value: JSON.stringify(charts) });
  useFrontendTool({
    name: "generateChart",
    description: "Visualize the ClickHouse query results on the dashboard.",
    parameters: chartSchema,
    handler: async (args) => {
      const chart = chartSchema.parse(args);
      setCharts(current => [...current, chart]);
      return "Chart added to the dashboard.";
    },
  }, []);
  return (
    <div className="grid grid-cols-1 gap-8 xl:grid-cols-2">
      {charts.length ? charts.map((chart, index) => (
        <section key={index}>
          <h2 className="mb-4 text-xl font-bold">{chart.title}</h2>
          <GenericChart {...chart} />
        </section>
      )) : <p className="rounded border border-neutral-700 p-12 text-neutral-400">Ask the assistant to chart your data.</p>}
    </div>
  );
}
