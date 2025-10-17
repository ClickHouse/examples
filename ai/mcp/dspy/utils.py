def print_dspy_result(prediction_result):
    """
    Simple function to print DSPy ReAct results in a clean, readable format
    """
    # Extract data from prediction result
    if hasattr(prediction_result, 'trajectory'):
        trajectory = prediction_result.trajectory
        reasoning = getattr(prediction_result, 'reasoning', '')
        process_result = getattr(prediction_result, 'process_result', '')
    elif isinstance(prediction_result, dict):
        trajectory = prediction_result.get('trajectory', {})
        reasoning = prediction_result.get('reasoning', '')
        process_result = prediction_result.get('process_result', '')
    else:
        print("Invalid prediction result format")
        return
    
    print("=" * 80)
    print("🤖 DSPy ReAct Result")
    print("=" * 80)
    
    # Extract and display steps
    step_index = 0
    while f'thought_{step_index}' in trajectory:
        print(f"\n📍 STEP {step_index + 1}")
        print("-" * 40)
        
        # Thought
        thought = trajectory.get(f'thought_{step_index}', '')
        if thought:
            print(f"🧠 THINKING: {thought}")
            print()
        
        # Tool call
        tool_name = trajectory.get(f'tool_name_{step_index}', '')
        tool_args = trajectory.get(f'tool_args_{step_index}', {})
        if tool_name:
            print(f"🔧 TOOL: {tool_name}")
            if tool_args:
                print(f"   Args: {tool_args}")
            print()
        
        # Observation/Result
        observation = trajectory.get(f'observation_{step_index}', '')
        if observation:
            print("📊 RESULT:")
            if isinstance(observation, list):
                # Handle query results nicely
                for i, item in enumerate(observation[:5]):  # Show first 5 items
                    try:
                        if isinstance(item, str) and item.strip().startswith('{'):
                            import json
                            parsed = json.loads(item)
                            if 'product_category' in parsed and 'review_count' in parsed:
                                print(f"   {i+1}. {parsed['product_category']}: {parsed['review_count']:,} reviews")
                            else:
                                print(f"   {i+1}. {parsed}")
                        else:
                            print(f"   {i+1}. {item}")
                    except:
                        print(f"   {i+1}. {item}")
                if len(observation) > 5:
                    print(f"   ... and {len(observation) - 5} more")
            elif isinstance(observation, str):
                if len(observation) > 200:
                    print(f"   {observation[:200]}...")
                else:
                    print(f"   {observation}")
            else:
                print(f"   {observation}")
            print()
        
        step_index += 1
    
    # Final sections
    if reasoning:
        print("\n🎯 REASONING")
        print("-" * 40)
        print(reasoning)
        print()
    
    if process_result:
        print("\n✅ FINAL RESULT")
        print("-" * 40)
        print(process_result)
    
    print("=" * 80)