# Murmuration (1.0.0) 🐦✨

Murmuration is a Dart framework designed for orchestrating multi-agent interactions using Google's Generative AI models. It aims to facilitate seamless agent coordination and function execution, providing an ergonomic interface for constructing complex AI workflows.

> [⚠️WARNING] If you plan to use this in production, ensure you have proper error handling and testing in place as interaction with AI models can be unpredictable.

> The name "Murmuration" is inspired by the mesmerizing flocking behavior of birds, symbolizing the framework's focus on coordinated agent interactions and dynamic workflows. 🐦💫

## Table of Contents 📚

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Key Features](#key-features)
- [Core Concepts](#core-concepts)
- [Progress Tracking](#progress-tracking)
- [Streaming Support](#streaming-support)
- [Debugging](#debugging)
- [Error Handling](#error-handling)
- [API Reference](#api-reference)
- [Best Practices](#best-practices)
- [Examples](#examples)
- [Contributing](#contributing)
- [License](#license)

## Installation ⚙️

Add to your `pubspec.yaml`:

```yaml
dependencies:
  murmuration: ^latest_version
  google_generative_ai: ^latest_version
```

Then run:

```bash
dart pub get
```

## Quick Start 🚀

```dart
import 'package:murmuration/murmuration.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

void main() async {
  final config = MurmurationConfig(
    apiKey: 'your-api-key',
    model: 'gemini-1.5-flash-latest',
    debug: false,
    stream: false,
    logger: MurmurationLogger()
  );

  final murmur = Murmuration(config);

  final result = await murmur.run(
    input: "Hello!",
    agentInstructions: {
      'role': 'You are a helpful assistant.'
    },
    stateVariables: {},  // Optional initial state
    tools: [],           // Optional tools
    functions: {},       // Optional function handlers
    onProgress: null     // Optional progress callback
  );

  print(result.output);
}
```

## Why Murmuration? 🤔

Murmuration is designed for situations where you need:

- Multiple specialized agents working together 🤝
- Complex function calling and tool usage with specific response formats 🔧
- State management and context preservation across agent interactions 📊
- Detailed progress tracking and logging 📈
- Real-time streaming of responses with configurable delay ⏳
- Integration with Google's Generative AI models 🌐

## Key Features 🌟

- **Streamlined Agent Management**: Create and coordinate multiple agents with distinct roles and capabilities
- **Function Registration**: Register custom functions with specific parameter types that agents can invoke
- **Tool Integration**: Add specialized tools with defined schemas for agent use
- **State Management**: Built-in state handling for maintaining context across agent interactions
- **Progress Tracking**: Detailed progress monitoring with timestamps and status updates
- **Streaming Support**: Real-time streaming of agent responses with configurable delays
- **Agent Chains**: Sequential execution of multiple agents with automatic state handoff

## Core Concepts 🧠

### Agents

Agents are the fundamental building blocks in Murmuration. Each agent is powered by Google's GenerativeModel and encapsulates:

- Instructions defining its behavior
- Available tools and functions
- State management capabilities
- Progress reporting mechanisms

```dart
final agent = murmur.createAgent(
  {'role': 'You analyze data and provide insights.'},
  currentAgentIndex: 1,      // Optional: for chain positioning
  totalAgents: 1,            // Optional: total agents in chain
  onProgress: (progress) {   // Optional: progress tracking
    print(progress.toString());
  }
);

// Registering a function with proper type annotation
agent.registerFunction(
  'analyzeData',
  (Map<String, dynamic> params) {
    // Analyze data logic here
    return 'Analysis complete';
  }
);
```

### Function Handlers and Response Format

Functions must follow a specific format for registration and invocation. The Agent class detects function calls by searching for the text "function:" in the model's response:

````dart
// Function handler type definition
typedef FunctionHandler = dynamic Function(Map<String, dynamic>);

// Registering a function
void registerDataFunction(Agent agent) {
  agent.registerFunction('processData', (Map<String, dynamic> params) {
    // Access context variables if available
    final contextVars = params['context_variables'];
    // Process data
    return {'result': 'Processed data'};
  });
}

// Function call format in agent responses ```dart
// The agent must return text in this EXACT format:
// function: functionName(param1: value1, param2: value2)
// Note: The format must match exactly, including spaces after colons
````

### Tools 🛠️

Tools must be defined with complete schemas and type-safe execution functions:

```dart
final dataTool = Tool(
  name: 'data_processor',
  description: 'Processes raw data into structured format',
  schema: {
    'type': 'object',
    'properties': {
      'data': {'type': 'string'},
      'format': {'type': 'string'}
    }
  },
  execute: (Map<String, dynamic> params) {
    // Tool execution logic
    return 'Processed result';
  }
);

agent.registerTool(dataTool);
```

### Agent Chains and State Management 🔗

Create sequences of agents with state handoff. Note that the handoff method only copies state variables and doesn't transfer other agent properties:

```dart
final result = await murmur.runAgentChain(
  input: "Analyze this data",
  agentInstructions: [
    {'role': 'You clean and prepare data'},
    {'role': 'You analyze prepared data'},
    {'role': 'You create summaries of analysis'}
  ],
  tools: [],                    // Optional tools shared across chain
  functions: {},                // Optional functions shared across chain
  logProgress: true,            // Enable progress logging
  onProgress: (progress) {      // Optional progress callback
    print(progress.toString());
  }
);

// Access chain results
print(result.finalOutput);          // Final chain output
print(result.results.length);       // Number of agent results
print(result.progress.length);      // Number of progress records
```

## Progress Tracking 📊

Progress tracking includes timestamps and detailed status information:

```dart
final result = await murmur.run(
  input: "Process this task",
  onProgress: (progress) {
    print('Agent ${progress.currentAgent}/${progress.totalAgents}');
    print('Status: ${progress.status}');
    print('Output: ${progress.output}');
    print('Time: ${progress.timestamp}');
  }
);
```

## Streaming Support 🌊

Enable real-time streaming with configurable delay. The streaming implementation uses GenerativeModel's response text, splitting it into chunks with a 50ms delay:

```dart
final config = MurmurationConfig(
  apiKey: 'your-api-key',
  stream: true,  // Enable streaming
  debug: true    // Optional: enable debug logging
);

final murmur = Murmuration(config);
final result = await murmur.run(
  input: "Stream this response",
  onProgress: (progress) {
    print('Streaming: ${progress.status}');
  }
);

// Stream includes 50ms delay between chunks
// Chunks are created by splitting the response text on spaces
await for (final chunk in result.stream!) {
  print(chunk);
}
```

Internal streaming implementation details:

- Uses StreamController to manage the stream
- Splits response text on spaces for chunk creation
- Adds artificial 50ms delay between chunks
- Reports progress for each chunk streamed

## Debugging 🐞

Enable comprehensive debug logging:

```dart
final config = MurmurationConfig(
  apiKey: 'your-api-key',
  debug: true,
  logger: MurmurationLogger(
    enabled: true,
    onLog: (message) {
      print('LOG: $message');
    },
    onError: (message) {
      print('ERROR: $message');
    }
  )
);
```

## Error Handling ⚠️

Comprehensive error handling with original error preservation:

```dart
try {
  final result = await murmur.run(
    input: "Process this",
    agentInstructions: {'role': 'Assistant'}
  );

  // Check for stream availability
  if (result.stream != null) {
    await for (final chunk in result.stream!) {
      // Handle streaming response
    }
  } else {
    // Handle regular response
    print(result.output);
  }
} on MurmurationError catch (e) {
  print('Murmuration Error: ${e.message}');
  if (e.originalError != null) {
    print('Original Error: ${e.originalError}');
  }
} catch (e) {
  print('Unexpected Error: $e');
}
```

## API Reference 📖

### MurmurationConfig

Configuration options for the Murmuration instance:

```dart
final config = MurmurationConfig(
  apiKey: 'required-api-key',
  model: 'gemini-1.5-flash-latest',  // Default model
  debug: false,                      // Default debug mode
  stream: false,                     // Default streaming mode
  logger: MurmurationLogger(         // Optional logger
    enabled: false,
    onLog: null,
    onError: null
  )
);
```

### Agent Functions

Core agent manipulation methods:

- `registerFunction(String name, FunctionHandler handler)`: Add custom function handlers
- `registerTool(Tool tool)`: Add specialized tools
- `updateState(Map<String, dynamic> newState)`: Modify agent state
- `handoff(Agent nextAgent)`: Transfer state variables to another agent
- `execute(String input)`: Run the agent with input

### Result Types

```dart
// Agent execution result
class AgentResult {
  final String output;
  final Map<String, dynamic> stateVariables;
  final List<String> toolCalls;
  final Stream<String>? stream;
  final List<AgentProgress>? progress;
}

// Chain execution result
class ChainResult {
  final List<AgentResult> results;
  final String finalOutput;
  final List<AgentProgress> progress;
}

// Progress tracking information
class AgentProgress {
  final int currentAgent;
  final int totalAgents;
  final String status;
  final String? output;
  final DateTime timestamp;
}
```

## Best Practices 🏆

1. **State Management**

   - Use immutable state operations with `updateState()`
   - Clear state between chain executions
   - Preserve context variables in state
   - Remember that handoff only copies state variables

2. **Function Design**

   - Always use `Map<String, dynamic>` for parameters
   - Follow the exact function call format in responses
   - Handle missing or invalid parameters
   - Test function call string parsing extensively

3. **Error Handling**

   - Catch `MurmurationError` separately
   - Preserve original errors
   - Log errors through MurmurationLogger
   - Handle GenerativeModel errors properly

4. **Progress Monitoring**

   - Implement `onProgress` callbacks
   - Track timing with timestamps
   - Log state transitions
   - Monitor streaming progress

5. **Tool Integration**

   - Define complete schemas
   - Include parameter validation
   - Document expected inputs/outputs
   - Test tool execution thoroughly

6. **Streaming**
   - Account for 50ms chunk delay
   - Handle stream availability
   - Implement proper stream cleanup
   - Consider chunk size implications

## Contributing 🤝

Guidelines for contributing to Murmuration:

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

Please ensure your code:

- Follows Dart conventions
- Is properly documented
- Handles errors appropriately
- Includes type annotations

## License 📜

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author ✍️

This project is authored by [Agniva Maiti](https://github.com/AgnivaMaiti).
