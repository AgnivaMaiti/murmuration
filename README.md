# Murmuration (2.0.0) 🐦✨

![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)

![murmurationpic](https://raw.githubusercontent.com/AgnivaMaiti/murmuration/refs/heads/main/assets/logo.png)

A robust Dart framework for orchestrating multi-agent interactions using Google's Generative AI models. Murmuration provides type-safe, thread-safe, and reliable systems for agent coordination, state management, and function execution.

> [⚠️WARNING] If you plan to use this in production, ensure you have proper error handling and testing in place as interaction with AI models can be unpredictable.

> The name "Murmuration" is inspired by the mesmerizing flocking behavior of birds, symbolizing the framework's focus on coordinated agent interactions and dynamic workflows. 🐦💫

## What's New in Murmuration 2.0.0 🐦

Version 2.0.0 introduces powerful new features and enhancements to improve your experience with Murmuration:

- **Enhanced Schema Validation**: Redesigned for type safety and stricter validation.
- **Thread-Safe State Management**: Immutable state with type-safe access methods.
- **Improved Error Handling**: New `MurmurationException` class for detailed error insights.
- **Message History Updates**: Persistent, thread-safe storage with automatic cleanup.
- **New Configuration Options**: Cache support, retry policies, and more.
- **Streaming Response Enhancements**: Better concurrency and progress tracking.

### Breaking Changes

This version includes significant changes that may require updates to your implementation. Please refer to the [Migration Guide](https://agnivamaiti.github.io/murmuration/migration-guide.html) for detailed steps to upgrade smoothly.

## Table of Contents 📚

- [Overview](#overview)
- [Installation](#installation)
- [Core Features](#core-features)
- [Usage Guide](#usage-guide)
  - [Basic Usage](#basic-usage)
  - [Advanced Usage](#advanced-usage)
  - [Streaming Responses](#streaming-responses)
  - [Schema Validation](#schema-validation)
  - [State Management](#state-management)
  - [Agent Chains](#agent-chains)
- [Architecture Overview](#architecture-overview)
- [Core Systems](#core-systems)
- [Real-World Examples](#real-world-examples)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)
- [Contributing](#contributing)
- [Tutorials](#tutorials)
- [License](#license)
- [Author](#author)

## Overview 🔍

Murmuration offers:

- Type-safe schema validation system for ensuring data integrity
- Thread-safe state management to prevent race conditions
- Robust error handling with detailed error reporting
- Message history management with persistence
- Tool and function integration for extended capabilities
- Agent chain orchestration for complex workflows
- Streaming response support for real-time processing
- Comprehensive logging for debugging and monitoring

## Installation ⚙️

Add to your `pubspec.yaml`:

```yaml
dependencies:
  murmuration: ^2.0.0
  google_generative_ai: ^latest_version
  shared_preferences: ^latest_version
  synchronized: ^latest_version
```

Then run:

```bash
dart pub get
```

## Core Features 🛠️

### Configuration

```dart
final config = MurmurationConfig(
  apiKey: 'your-api-key',
  model: 'gemini-1.5-pro',  // Specify the model to use
  debug: true,              // Enable debug mode for verbose logging
  stream: false,            // Disable streaming by default
  logger: MurmurationLogger(enabled: true),  // Enable logging
  timeout: Duration(seconds: 30),  // Set request timeout
  maxRetries: 3,           // Number of retry attempts
  retryDelay: Duration(seconds: 1),  // Delay between retries
  enableCache: true,       // Enable response caching
  cacheTimeout: Duration(hours: 1)  // Cache expiration time
);
```

### Error Handling

Murmuration uses the `MurmurationException` class for error handling. This allows you to catch and handle errors gracefully during agent execution. Example:

```dart
try {
  final result = await agent.execute("Process data");
} on MurmurationException catch (e) {
  print('Error: ${e.message}');  // Human-readable error message
  print('Original error: ${e.originalError}');  // Original exception
  print('Stack trace: ${e.stackTrace}');  // Full stack trace
}
```

### Logging

You can enable logging using the `MurmurationLogger` class to track events and errors:

```dart
final logger = MurmurationLogger(
  enabled: true,
  onLog: (message) => print('Log: $message'),  // Log handler
  onError: (message, error, stackTrace) {      // Error handler
    print('Error: $message');
    print('Details: $error');
  }
);
```

## Architecture Overview 🏗️

Murmuration is built on several core systems that work together to provide a robust framework:

1. **Core Systems**

   - Error Handling System: Manages exceptions and error reporting
   - Schema Validation System: Ensures data integrity
   - State Management System: Handles thread-safe state updates
   - Message History System: Manages conversation context
   - Logging System: Tracks events and errors
   - Configuration Management: Handles framework settings
   - Agent Management: Coordinates AI model interactions
   - Tool and Function Management: Handles external integrations
   - Execution and Progress Tracking: Monitors workflow status

2. **Key Components**
   - `Murmuration`: Main class orchestrating all components
   - `Agent`: Core class handling AI model interactions
   - `MurmurationConfig`: Configuration management
   - `MessageHistory`: Thread-safe message management
   - `ImmutableState`: Thread-safe state management
   - `SchemaField`: Type-safe validation system

## Core Systems 🔧

### 1. Message History

Thread-safe message management with persistence:

```dart
final history = MessageHistory(
  threadId: 'user-123',       // Unique thread identifier
  maxMessages: 50,            // Maximum messages to retain
  maxTokens: 4000             // Maximum total tokens
);

await history.addMessage(Message(
  role: 'user',
  content: 'Hello!',
  timestamp: DateTime.now()
));

await history.save();    // Persist to storage
await history.load();    // Load from storage
await history.clear();   // Clear history
```

### 2. State Management

Thread-safe, immutable state operations:

```dart
final state = ImmutableState()
  .copyWith({
    'user': {'name': 'John', 'age': 30},
    'preferences': {'theme': 'dark'}
  });

final userName = state.get<String>('user.name');  // Type-safe access
```

## Usage Guide 📖

### Basic Usage

```dart
void main() async {
  final murmur = Murmuration(config);

  final agent = await murmur.createAgent(
    {'role': 'Assistant', 'context': 'Data processing'},
    currentAgentIndex: 1,
    totalAgents: 1
  );

  final result = await agent.execute("Process this data");
  print(result.output);
}
```

### Advanced Usage

#### Custom Schema Fields

```dart
class DateTimeSchemaField extends SchemaField<DateTime> {
  final DateTime? minDate;
  final DateTime? maxDate;

  const DateTimeSchemaField({
    required String description,
    this.minDate,
    this.maxDate,
    bool required = true,
  }) : super(
    description: description,
    required: required,
  );

  @override
  bool isValidType(Object? value) =>
    value == null ||
    value is DateTime ||
    (value is String && DateTime.tryParse(value) != null);

  @override
  bool validate(DateTime? value) {
    if (value == null) return !required;
    if (minDate != null && value.isBefore(minDate!)) return false;
    if (maxDate != null && value.isAfter(maxDate!)) return false;
    return true;
  }

  @override
  DateTime? convert(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

// Usage example:
final schema = OutputSchema(
  fields: {
    'name': StringSchemaField(
      description: 'User name',
      minLength: 2,
      required: true
    ),
    'birthDate': DateTimeSchemaField(
      description: 'Birth date',
      minDate: DateTime(1900),
      maxDate: DateTime.now(),
      required: true
    )
  }
);
```

### Streaming Responses 🌊

```dart
final config = MurmurationConfig(
  apiKey: 'your-api-key',
  stream: true  // Enable streaming
);

final agent = await murmur.createAgent({'role': 'Assistant'});
final result = await agent.execute("Generate a long story");

if (result.stream != null) {
  await for (final chunk in result.stream!) {
    print(chunk);  // Process each chunk as it arrives
  }
}
```

### Agent Chains ⛓️

Example of a complex document processing chain:

```dart
final result = await murmur.runAgentChain(
  input: documentText,
  agentInstructions: [
    {
      'role': 'Document Parser',
      'context': 'Extract key information from documents'
    },
    {
      'role': 'Data Analyzer',
      'context': 'Analyze and categorize extracted information'
    },
    {
      'role': 'Report Generator',
      'context': 'Generate comprehensive report'
    }
  ],
  tools: [
    Tool(
      name: 'document_parser',
      description: 'Parses document text',
      parameters: {'text': StringSchemaField(description: 'Document text')},
      execute: (params) async => parseDocument(params['text'])
    )
  ],
  functions: {
    'analyze': (params) async => analyzeData(params),
    'generate_report': (params) async => generateReport(params)
  },
  logProgress: true,
  onProgress: (progress) {
    print('Progress: ${progress.currentAgent}/${progress.totalAgents}');
    print('Status: ${progress.status}');
  }
);

print('Final report: ${result.finalOutput}');
```

## Real-World Examples 💡

### Customer Support Bot

```dart
final supportBot = await murmur.createAgent({
  'role': 'Customer Support',
  'context': '''
    You are a helpful customer support agent.
    Follow company guidelines and maintain professional tone.
    Escalate sensitive issues to human support.
  '''
});

// Add ticket management tool
supportBot.addTool(Tool(
  name: 'create_ticket',
  description: 'Creates support ticket',
  parameters: {
    'priority': StringSchemaField(
      description: 'Ticket priority',
      enumValues: ['low', 'medium', 'high']
    ),
    'category': StringSchemaField(description: 'Issue category')
  },
  execute: (params) async => createSupportTicket(params)
));

final response = await supportBot.execute(userQuery);
```

### Data Processing Pipeline

```dart
final pipeline = await murmur.runAgentChain(
  input: rawData,
  agentInstructions: [
    {'role': 'Data Validator'},
    {'role': 'Data Transformer'},
    {'role': 'Data Analyzer'},
    {'role': 'Report Generator'}
  ],
  tools: [
    Tool(
      name: 'data_validation',
      description: 'Validates data format',
      execute: validateData
    ),
    Tool(
      name: 'data_transform',
      description: 'Transforms data format',
      execute: transformData
    )
  ]
);
```

## Troubleshooting 🔍

### Common Issues

1. **Timeout Errors**

   ```dart
   // Increase timeout duration
   final config = MurmurationConfig(
     timeout: Duration(minutes: 2),
     maxRetries: 5
   );
   ```

2. **Memory Issues**

   ```dart
   // Manage message history
   final config = MurmurationConfig(
     maxMessages: 30,
     maxTokens: 2000
   );
   ```

3. **State Management Issues**
   ```dart
   // Use proper state copying
   final newState = state.copyWith(newData);
   // Don't modify state directly
   state._data['key'] = value;  // Wrong!
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

1. Fork the repository
2. Create a feature branch
3. Implement your changes
4. Add tests
5. Submit a pull request

Please ensure your code:

- Follows Dart conventions
- Includes proper documentation
- Has comprehensive error handling
- Includes appropriate tests
- Maintains type safety

## Tutorials ✨

Explore the following tutorials to learn how to build applications using the Murmuration framework:

- [Building a Chatbot with Murmuration and Flutter](https://agnivamaiti.github.io/murmuration/chatbot_tutorial.html)
- [Building a Text Classifier with Murmuration and Flutter](https://agnivamaiti.github.io/murmuration/text_classifier_tutorial.html)

These tutorials provide step-by-step instructions and code examples to help you get started with creating your own applications using Murmuration.

## License 📜

This project is licensed under the MIT License - see the [LICENSE](https://github.com/AgnivaMaiti/murmuration/blob/main/LICENSE) file for details.

## Author ✍️

This project is authored and maintained by [Agniva Maiti](https://github.com/AgnivaMaiti).
