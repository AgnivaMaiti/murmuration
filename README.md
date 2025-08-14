# Murmuration 🐦✨

[![Version](https://img.shields.io/badge/version-3.1.0-blue.svg)](https://pub.dev/packages/murmuration)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.0.0%2B-blue.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.0.0%2B-blue.svg)](https://dart.dev)
[![Test Status](https://github.com/AgnivaMaiti/murmuration/actions/workflows/test.yaml/badge.svg)](https://github.com/AgnivaMaiti/murmuration/actions)
[![Coverage](https://codecov.io/gh/AgnivaMaiti/murmuration/branch/main/graph/badge.svg)](https://codecov.io/gh/AgnivaMaiti/murmuration)
[![Pub Points](https://img.shields.io/pub/points/murmuration)](https://pub.dev/packages/murmuration/score)
[![Pub Popularity](https://img.shields.io/pub/popularity/murmuration)](https://pub.dev/packages/murmersion/score)

![murmurationpic](https://raw.githubusercontent.com/AgnivaMaiti/murmuration/refs/heads/main/assets/logo.png)

A powerful and flexible AI agent framework for building intelligent applications with support for multiple LLM providers and tool chaining. Murmuration provides type-safe, thread-safe, and reliable systems for agent coordination, state management, and function execution.

> [⚠️WARNING] If you plan to use this in production, ensure you have proper error handling and testing in place as interaction with AI models can be unpredictable.

> The name "Murmuration" is inspired by the mesmerizing flocking behavior of birds, symbolizing the framework's focus on coordinated agent interactions and dynamic workflows. 🐦💫

## Features 🌟

### 🤖 Multiple LLM Provider Support
- **OpenAI**: All GPT-3.5 and GPT-4 models with streaming
- **Google**: Gemini Pro and other supported models with streaming
- **Anthropic**: Claude 3 models (Opus, Sonnet, Haiku) with streaming
- Extensible provider system with consistent interface
- Automatic rate limiting and retry logic

### 🔄 Flexible Agent System
- Chain multiple agents with different LLM providers
- Tool composition and function calling
- Thread-safe state management
- Persistent message history
- Asynchronous execution model

### 🛠️ Tool Management
- Built-in tool registry with namespacing
- Custom tool creation with parameter validation
- Async/await support for long-running operations
- Tool chaining and composition
- Automatic tool documentation generation

### 📝 State Management
- Thread-safe operations with mutex locks
- Immutable state with change tracking
- Type-safe access with schema validation
- Cross-agent state synchronization
- Pluggable persistence backends

### 🔍 Schema Validation
- Strong type checking for inputs/outputs
- Custom validators and transformers
- Automatic schema generation from Dart types
- Detailed error reporting with suggestions
- JSON Schema compatibility

### 📊 Logging & Monitoring
- Structured logging with different log levels
- Performance metrics collection
- Distributed tracing support
- Integration with monitoring tools
- Debug utilities for development

### ⚡ Resource Management
- Connection pooling for HTTP clients
- Adaptive rate limiting with backoff
- Memory-efficient streaming
- Cache integration with TTL support
- Automatic resource cleanup

### 🔒 Security
- Secure API key handling with environment variables
- Input sanitization and validation
- Role-based access control
- Request signing for supported providers
- Audit logging for sensitive operations

## 🚀 Getting Started

### Prerequisites

- Dart SDK: ^3.0.0
- Flutter: ^3.0.0 (for Flutter projects)
- API keys for your preferred LLM providers (OpenAI, Anthropic, or Google)

### Installation

Add Murmuration to your `pubspec.yaml`:

```yaml
dependencies:
  murmuration: ^3.1.0
  flutter_dotenv: ^5.1.0  # For secure environment variable handling
  shared_preferences: ^2.2.0  # For local storage (optional but recommended)
```

Then install dependencies:

```bash
flutter pub get  # For Flutter projects
# or
dart pub get    # For pure Dart projects
```

### Environment Setup

1. Create a `.env` file in your project root:
   ```env
   # Required API Keys (at least one)
   OPENAI_API_KEY=your_openai_api_key
   ANTHROPIC_API_KEY=your_anthropic_api_key
   GEMINI_API_KEY=your_google_api_key
   
   # Optional Configuration
   MURMURATION_DEBUG=true  # Enable debug logging
   ```

2. Add `.env` to your `.gitignore` file to keep your API keys secure.

## 📦 Example Apps

Check out the example implementations in the `example/` directory:

1. **Chatbot** - A simple chat interface with streaming responses
2. **Text Classifier** - Text classification with multiple providers
3. **Smart Task Manager** - AI-powered task management with natural language processing

To run an example:
```bash
cd example/
flutter run -d chrome  # For web
# or
flutter run -d android  # For Android
# or
flutter run -d ios  # For iOS
```

### Secure API Key Management

For production applications, never hardcode API keys. Use environment variables or a secrets manager:

1. Create a `.env` file in your project root (add to `.gitignore`):
   ```
   OPENAI_API_KEY=your_openai_key
   ANTHROPIC_API_KEY=your_anthropic_key
   GOOGLE_API_KEY=your_google_key
   ```

2. Load environment variables at startup:
   ```dart
   import 'package:flutter_dotenv/flutter_dotenv.dart';
   
   void main() async {
     await dotenv.load(fileName: ".env");
     // Your app initialization
   }
   ```

For more details, see our [API Key Handling Guide](docs/API_KEY_HANDLING.md).

## 🎯 Basic Usage

### Initialize Murmuration

```dart
import 'package:murmuration/murmuration.dart';

final config = MurmurationConfig(
  apiKey: dotenv.env['ANTHROPIC_API_KEY']!,
  provider: LLMProvider.anthropic,
  modelConfig: ModelConfig(
    modelName: 'claude-3-opus-20240229',
    temperature: 0.7,
    maxTokens: 1000,
  ),
  // Optional: Configure caching
  cacheConfig: CacheConfig(
    enabled: true,
    ttl: Duration(hours: 1),
  ),
);

final murmuration = Murmuration(config);
```

### Create and Use an Agent

```dart
// Create a simple agent
final agent = await murmuration.createAgent(
  systemPrompt: 'You are a helpful assistant',
  // Optional: Configure tools and state
  tools: [
    Tool(
      name: 'get_weather',
      description: 'Get current weather for a location',
      parameters: {
        'location': {'type': 'string', 'required': true},
        'unit': {'type': 'string', 'enum': ['celsius', 'fahrenheit']},
      },
      execute: (args) async {
        // Implement your weather API call
        return '72°F and sunny in ${args['location']}';
      },
    ),
  ],
);

// Execute the agent
final result = await agent.execute(
  'What\'s the weather like in San Francisco?',
  // Optional: Pass additional context
  context: {'user_id': '123'},
);

print(result.output);
```

### Streaming Responses

```dart
final stream = agent.executeStream(
  'Tell me a story about a magical forest',
);

await for (final chunk in stream) {
  if (chunk.isDone) {
    print('\nFinished! Tokens used: ${chunk.usage?.totalTokens}');
  } else {
    // Print each chunk as it arrives
    print(chunk.content);
  }
}
```

## 🔧 Advanced Usage

### Agent Chaining

Chain multiple agents to handle complex workflows:

```dart
// Create specialized agents
final researchAgent = await murmuration.createAgent(
  systemPrompt: 'You are a research assistant',
  modelConfig: ModelConfig(modelName: 'gpt-4'),
);

final writingAgent = await murmuration.createAgent(
  systemPrompt: 'You are a content writer',
  modelConfig: ModelConfig(modelName: 'claude-3-opus'),
);

// Chain the agents
final result = await researchAgent
    .chain(writingAgent)
    .execute('Research and write a summary about quantum computing');
```

### State Management

Manage state across agent interactions:

```dart
// Create stateful agent
final agent = await murmuration.createAgent(
  systemPrompt: 'You are a helpful assistant',
  initialState: {
    'userPreferences': {
      'language': 'English',
      'tone': 'professional',
    },
  },
);

// Update state
await agent.updateState((state) {
  return state..['userPreferences']['tone'] = 'casual';
});

// Access state in tools
agent.addTool(
  Tool(
    name: 'get_preferences',
    description: 'Get user preferences',
    execute: (_, {required state}) {
      return state?['userPreferences'] ?? {};
    },
  ),
);
```

### Error Handling

Handle errors gracefully:

```dart
try {
  final result = await agent.execute('Do something risky');
  print(result.output);
} on RateLimitException catch (e) {
  print('Rate limited. Retry after: ${e.retryAfter}');
} on APIException catch (e) {
  print('API Error (${e.statusCode}): ${e.message}');
} catch (e, stackTrace) {
  print('Unexpected error: $e');
  // Log the error
  logger.error('Agent execution failed', error: e, stackTrace: stackTrace);
}
```

## 🏗️ Custom Tools

Create custom tools by extending the `Tool` class:

```dart
class WebSearchTool extends Tool {
  final WebSearchService _searchService;
  
  WebSearchTool(this._searchService)
      : super(
          name: 'web_search',
          description: 'Search the web for information',
          parameters: {
            'query': {'type': 'string', 'required': true},
            'max_results': {'type': 'integer', 'default': 5},
          },
          // Mark as requiring authentication
          requiresAuth: true,
          // Add metadata for documentation
          metadata: {
            'category': 'web',
            'version': '1.0.0',
          },
        );

  @override
  Future<String> execute(
    Map<String, dynamic> args, {
    required Map<String, dynamic> state,
  }) async {
    // Input validation is handled automatically
    final query = args['query'] as String;
    final maxResults = args['max_results'] as int;
    
    try {
      final results = await _searchService.search(
        query,
        maxResults: maxResults,
      );
      
      // Format results for the LLM
      return results
          .map((r) => '${r.title}: ${r.snippet}')
          .join('\n\n');
    } catch (e, stackTrace) {
      // Log the error
      logger.error('Web search failed', error: e, stackTrace: stackTrace);
      
      // Rethrow with a user-friendly message
      throw ToolExecutionException(
        'Failed to perform web search',
        originalError: e,
      );
    }
  }
}

// Register your tool
final searchTool = WebSearchTool(webSearchService);
ToolRegistry.register(searchTool);

// Now the tool is available to all agents
final agent = await murmuration.createAgent(
  systemPrompt: 'You are a helpful assistant with web search capabilities',
  tools: [searchTool],
);

// The agent can now use the web_search tool
final result = await agent.execute(
  'Find the latest news about artificial intelligence',
);
```

## 📚 Documentation

For detailed documentation, check out:

- [API Reference](https://pub.dev/documentation/murmuration/latest/)
- [Examples](example/README.md)
- [Contributing Guide](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

## 🔍 Examples

### Basic Usage

```dart
import 'package:murmuration/murmuration.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load();
  
  // Initialize with your preferred provider
  final murmuration = Murmuration(
    provider: LLMProvider.anthropic,  // or .openai, .google
    apiKey: dotenv.env['ANTHROPIC_API_KEY']!,
    modelConfig: ModelConfig(
      modelName: 'claude-3-opus-20240229',
      temperature: 0.7,
      maxTokens: 1000,
    ),
  );

  // Create an agent
  final agent = await murmuration.createAgent(
    systemPrompt: 'You are a helpful assistant',
  );

  // Execute a prompt
  final response = await agent.execute('Hello, world!');
  print(response.output);
  
  // Clean up
  await murmuration.dispose();
}
```

### Streaming Responses

```dart
final result = await agent.execute(
  'Tell me a story about AI',
  stream: true,
);

// Handle streaming response
await for (final chunk in result.stream!) {
  print(chunk);
}
```

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by the coordinated movement of starlings in murmuration
- Built with ❤️ using Dart and Flutter
- Thanks to all [contributors](https://github.com/yourusername/murmuration/graphs/contributors) who have helped shape this project.

---

Made with [murmuration](https://github.com/yourusername/murmuration) 🐦✨
}
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
