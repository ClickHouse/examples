"use client";
import { CopilotKit, CopilotSidebar, useDefaultRenderTool } from "@copilotkit/react-core/v2";
import "@copilotkit/react-ui/v2/styles.css";
import ChartsGrid from "./ChartsGrid";

function Dashboard() {
  useDefaultRenderTool({
    render: ({ name, status, result }) => (
      <details className="rounded border border-neutral-600 p-3">
        <summary>{name}: {status}</summary>
        <pre className="max-h-64 overflow-auto whitespace-pre-wrap text-xs">
          {JSON.stringify({ result }, null, 2)}
        </pre>
      </details>
    ),
  });
  return (
    <>
      <main className="p-8 pr-8 lg:pr-[440px]">
        <h1 className="mb-6 text-2xl font-bold">Custom analytics dashboard</h1>
        <ChartsGrid />
      </main>
      <CopilotSidebar defaultOpen />
    </>
  );
}
export default function Analytics() {
  return <CopilotKit runtimeUrl="/api/copilotkit"><Dashboard /></CopilotKit>;
}
