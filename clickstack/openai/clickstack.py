# /// script
# requires-python = ">=3.9"
# dependencies = [
#     "openai",
#     "opentelemetry-sdk",
#     "openinference-instrumentation-openai",
#     "opentelemetry-exporter-otlp",
# ]
# ///

import openai
import os

from openinference.instrumentation.openai import OpenAIInstrumentor
from opentelemetry.sdk import trace as trace_sdk
from opentelemetry.sdk.trace.export import ConsoleSpanExporter, SimpleSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

tracer_provider = trace_sdk.TracerProvider()

api_key = os.getenv("HYPERDX_API_KEY", "your_api_key_here")
otlp_exporter = OTLPSpanExporter(
    endpoint="http://localhost:4318/v1/traces",
    timeout=10,
    headers={
        "authorization": api_key
    }
)

tracer_provider.add_span_processor(SimpleSpanProcessor(otlp_exporter))
tracer_provider.add_span_processor(SimpleSpanProcessor(ConsoleSpanExporter()))

OpenAIInstrumentor().instrument(tracer_provider=tracer_provider)

if __name__ == "__main__":
    client = openai.OpenAI()
    response = client.chat.completions.create(
        model="gpt-3.5-turbo",
        messages=[{"role": "user", "content": "Write a haiku."}],
        max_tokens=20,
        stream=True,
        stream_options={"include_usage": True},
    )
    for chunk in response:
        if chunk.choices and (content := chunk.choices[0].delta.content):
            print(content, end="")
