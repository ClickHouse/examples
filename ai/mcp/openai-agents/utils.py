"""Display SDK stream events without interpreting tool-result text as status."""
def simple_render_chunk(chunk):
    if chunk.type == "run_item_stream_event":
        if chunk.name == "tool_called":
            item = chunk.item.raw_item
            print(f"\nTool: {getattr(item, 'name', 'tool')}({getattr(item, 'arguments', '')})")
        elif chunk.name == "tool_output":
            print(f"\nTool output: {str(chunk.item.output)[:1000]}")
    elif chunk.type == "raw_response_event" and chunk.data.type == "response.output_text.delta":
        print(chunk.data.delta, end="", flush=True)
