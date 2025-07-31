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

from openinference.instrumentation.openai import OpenAIInstrumentor
from opentelemetry.sdk import trace as trace_sdk
from opentelemetry.sdk.trace.export import ConsoleSpanExporter, SimpleSpanProcessor

tracer_provider = trace_sdk.TracerProvider()
tracer_provider.add_span_processor(SimpleSpanProcessor(ConsoleSpanExporter()))

OpenAIInstrumentor().instrument(tracer_provider=tracer_provider)

if __name__ == "__main__":
    client = openai.OpenAI()
    response = client.chat.completions.create(
        model="gpt-3.5-turbo",
        messages=[{"role": "user", "content": "Write a haiku about playing tennis."}],
        stream=True,
        stream_options={"include_usage": True},
    )
    for chunk in response:
        if chunk.choices and (content := chunk.choices[0].delta.content):
            print(content, end="")
