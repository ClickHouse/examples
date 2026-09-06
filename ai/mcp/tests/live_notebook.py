"""Execute an installed notebook with Luna and the shared local/Cloud fixture.

This makes paid OpenAI calls. Install the selected example's requirements first.
Notebook files and their cleared outputs are not modified.
"""
import ast
import asyncio
import contextlib
import io
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SUPPORTED = {
    "agno", "crewai", "dspy", "langchain", "llamaindex", "mcp-agent",
    "microsoft-agent-framework", "openai-agents", "pydanticai", "upsonic",
}
PROMPT = (
    "Run SELECT region, sum(revenue) AS revenue FROM mcp_demo.sales "
    "GROUP BY region ORDER BY region using ClickHouse MCP. "
    "Reply with just region and revenue."
)

async def main(name):
    if name not in SUPPORTED:
        raise ValueError(f"Choose one of: {', '.join(sorted(SUPPORTED))}")
    if not os.getenv("OPENAI_API_KEY"):
        raise ValueError("Export OPENAI_API_KEY before running this paid test")
    if os.getenv("OPENAI_MODEL", "gpt-5.6-luna") != "gpt-5.6-luna":
        raise ValueError("This inexpensive live check is restricted to gpt-5.6-luna")
    os.environ["LLM_PROVIDER"] = "openai"
    os.environ["OPENAI_MODEL"] = "gpt-5.6-luna"
    os.environ["MCP_PROMPT"] = PROMPT
    os.environ.setdefault("OTEL_SDK_DISABLED", "true")
    os.environ.setdefault("CREWAI_TELEMETRY_DISABLED", "true")
    directory = ROOT / name
    os.chdir(directory)
    sys.path.insert(0, str(directory))
    scope = {"__name__": "__live_notebook__"}
    notebook = json.loads(next(directory.glob("*.ipynb")).read_text())
    output = io.StringIO()
    try:
        with contextlib.redirect_stdout(output):
            for index, cell in enumerate(notebook["cells"]):
                if cell["cell_type"] != "code":
                    continue
                source = "".join(cell["source"])
                if source.lstrip().startswith(("%", "!")):
                    continue
                code = compile(source, f"{name}:cell-{index}", "exec", ast.PyCF_ALLOW_TOP_LEVEL_AWAIT)
                result = eval(code, scope)
                if asyncio.iscoroutine(result):
                    await result
    finally:
        print(output.getvalue())
    answer = output.getvalue()
    assert all(value in answer for value in ("North", "250", "South", "500")), "Fixture answer missing"
    print(f"PASS {name}: live Luna fixture answer")

if __name__ == "__main__":
    asyncio.run(main(sys.argv[1]))
