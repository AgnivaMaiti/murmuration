# Murmuration 🐦✨

[![Version](https://img.shields.io/badge/version-3.0.0-blue.svg)](https://pub.dev/packages/murmuration)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.0.0-blue.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.0.0-blue.svg)](https://dart.dev)

![murmurationpic](https://raw.githubusercontent.com/AgnivaMaiti/murmuration/refs/heads/main/assets/logo.png)

A powerful and flexible AI agent framework for building intelligent applications with support for multiple LLM providers and tool chaining. Murmuration provides type-safe, thread-safe, and reliable systems for agent coordination, state management, and function execution.

> [⚠️WARNING] If you plan to use this in production, ensure you have proper error handling and testing in place as interaction with AI models can be unpredictable.

> The name "Murmuration" is inspired by the mesmerizing flocking behavior of birds, symbolizing the framework's focus on coordinated agent interactions and dynamic workflows. 🐦💫

## Features 🌟

- 🤖 **Multiple LLM Provider Support**
  - OpenAI GPT models
  - Google's Generative AI
  - Anthropic's Claude
  - Extensible provider system

- 🔄 **Flexible Agent System**
  - Chain multiple agents
  - Tool composition
  - State management
  - Message history

- 🛠️ **Tool Management**
  - Built-in tool registry
  - Custom tool creation
  - Parameter validation
  - Async execution

- 📝 **State Management**
  - Thread-safe operations
  - Immutable state
  - Type-safe access
  - Persistence support

- 🔍 **Schema Validation**
  - Input/output validation
  - Type checking
  - Custom validators
  - Error reporting

- 📊 **Logging & Monitoring**
  - Structured logging
  - Performance metrics
  - Error tracking
  - Debug support

- ⚡ **Resource Management**
  - Memory optimization
  - Connection pooling
  - Rate limiting
  - Cache support

- 🔒 **Security**
  - Secure API key handling
  - Input sanitization
  - Rate limiting
  - Access control

## Getting Started 🚀

### Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  murmuration: ^3.0.0
```

### Basic Usage

```dart
import 'package:murmuration/murmuration.dart';

void main() async {
  // Initialize configuration
  final config = MurmurationConfig(
    apiKey: 'your-api-key',
    modelConfig: ModelConfig(
      modelName: 'gpt-3.5-turbo',
      maxTokens: 1000,
      temperature: 0.7,
    ),
  );

  // Create an agent
  final agent = await Agent.builder()
    .withConfig(config)
    .withState({'systemMessage': 'You are a helpful assistant'})
    .build();

  // Execute the agent
  final result = await agent.execute('Hello, how can you help me?');
  print(result.output);
}
```

### Tool Chaining

```dart
// Create a tool chain
final chain = ToolChain(
  name: 'data-processing',
  description: 'Process and analyze data',
  tools: [
    Tool(
      name: 'fetch-data',
      description: 'Fetch data from API',
      parameters: {
        'url': {'type': 'string', 'required': true},
        'method': {'type': 'string', 'required': true},
      },
      execute: (args) async {
        // Implementation
      },
    ),
    Tool(
      name: 'analyze-data',
      description: 'Analyze the fetched data',
      parameters: {
        'data': {'type': 'object', 'required': true},
      },
      execute: (args) async {
        // Implementation
      },
    ),
  ],
);

// Execute the chain
final result = await chain.execute({'url': 'https://api.example.com/data'});
```

## Advanced Features 🎯

### Custom Tools

Create custom tools by extending the `Tool` class:

```dart
class CustomTool extends Tool {
  CustomTool()
      : super(
          name: 'custom-tool',
          description: 'A custom tool implementation',
          parameters: {
            'input': {'type': 'string', 'required': true},
          },
        );

  @override
  Future<String> execute(Map<String, dynamic> args) async {
    // Implementation
    return 'Result';
  }
}
```

### Agent Chains

Create complex agent chains for sophisticated workflows:

```dart
final chain = await AgentChain.builder()
  .withConfig(config)
  .withState({'context': 'Processing data'})
  .addAgent(agent1)
  .addAgent(agent2)
  .build();

final result = await chain.execute('Process this data');
```

### Schema Validation

Define output schemas for validation:

```dart
final schema = OutputSchema({
  'type': 'object',
  'properties': {
    'result': {'type': 'string'},
    'confidence': {'type': 'number'},
  },
  'required': ['result'],
});

final agent = await Agent.builder()
  .withConfig(config)
  .withOutputSchema(schema)
  .build();
```

### Error Handling

Comprehensive error handling with custom exceptions:

```dart
try {
  final result = await agent.execute('Process data');
} on MurmurationException catch (e) {
  print('Error: ${e.message}');
  print('Original error: ${e.originalError}');
  print('Stack trace: ${e.stackTrace}');
}
```

### Logging

Configure logging for debugging and monitoring:

```dart
final logger = MurmurationLogger(
  enabled: true,
  onLog: (message) => print('Log: $message'),
  onError: (message, error, stackTrace) {
    print('Error: $message');
    print('Details: $error');
  }
);
```

## Real-World Examples 💡

### Customer Support Bot

```dart
final supportBot = await Agent.builder()
  .withConfig(config)
  .withState({
    'role': 'Customer Support',
    'context': '''
      You are a helpful customer support agent.
      Follow company guidelines and maintain professional tone.
      Escalate sensitive issues to human support.
    '''
  })
  .addTool(Tool(
    name: 'create_ticket',
    description: 'Creates support ticket',
    parameters: {
      'priority': {'type': 'string', 'enum': ['low', 'medium', 'high']},
      'category': {'type': 'string'}
    },
    execute: (params) async => createSupportTicket(params)
  ))
  .build();

final response = await supportBot.execute(userQuery);
```

### Data Processing Pipeline

```dart
final pipeline = await AgentChain.builder()
  .withConfig(config)
  .withState({'context': 'Data processing pipeline'})
  .addAgent(Agent.builder()
    .withState({'role': 'Data Validator'})
    .build())
  .addAgent(Agent.builder()
    .withState({'role': 'Data Transformer'})
    .build())
  .addAgent(Agent.builder()
    .withState({'role': 'Data Analyzer'})
    .build())
  .addAgent(Agent.builder()
    .withState({'role': 'Report Generator'})
    .build())
  .build();

final result = await pipeline.execute(rawData);
```

## Best Practices 🏆

1. **Error Handling**
   - Always wrap agent execution in try-catch blocks
   - Implement proper retry mechanisms
   - Log errors comprehensively
   - Handle timeouts appropriately

2. **Performance**
   - Enable caching for repetitive tasks
   - Implement cleanup mechanisms
   - Monitor memory usage
   - Use appropriate timeout values

3. **Security**
   - Validate all inputs
   - Handle sensitive data carefully
   - Implement proper access controls
   - Monitor API usage

4. **Message History**
   - Set appropriate message limits
   - Implement cleanup policies
   - Handle thread IDs carefully
   - Monitor storage usage

## Contributing 🤝

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## License 📜

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support 💬

For support, please:
- Open an issue in the [GitHub repository](https://github.com/AgnivaMaiti/murmuration/issues)
- Check the [documentation](https://agnivamaiti.github.io/murmuration)
- Contact the maintainers

## Author ✍️

This project is authored and maintained by [Agniva Maiti](https://github.com/AgnivaMaiti).
