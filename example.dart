import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:murmuration/murmuration.dart';

void main() async {
  // Load environment variables
  await dotenv.load(fileName: ".env");
  
  // Example 1: Basic Chat with Streaming
  await runBasicExample();
  
  // Example 2: Using Tools
  await runToolExample();
  
  // Example 3: Agent Chaining
  await runAgentChainExample();
}

/// Example 1: Basic chat with streaming and error handling
Future<void> runBasicExample() async {
  print('\n=== Basic Chat Example with Streaming ===');
  
  final config = MurmurationConfig(
    provider: LLMProvider.anthropic,
    apiKey: dotenv.env['ANTHROPIC_API_KEY']!,
    modelConfig: ModelConfig(
      modelName: 'claude-3-sonnet-20240229',
      temperature: 0.7,
      maxTokens: 1000,
    ),
    // Enable caching for faster responses to similar queries
    cacheConfig: CacheConfig(
      enabled: true,
      ttl: Duration(minutes: 30),
    ),
  );
  
  final murmuration = Murmuration(config);
  
  try {
    // Create an agent with system prompt
    final agent = await murmuration.createAgent(
      systemPrompt: 'You are a helpful assistant. '
          'Provide clear, concise, and accurate responses.',
    );
    
    final prompt = 'Explain quantum computing in simple terms';
    print('\nPrompt: $prompt');
    
    print('\nStreaming response:');
    
    // Using streaming API
    final stream = agent.executeStream(prompt);
    
    // Process the stream
    await for (final chunk in stream) {
      if (chunk.isDone) {
        print('\n\n--- Response Complete ---');
        print('Tokens used: ${chunk.usage?.totalTokens}');
      } else {
        // Print each chunk as it arrives
        print(chunk.content);
      }
    }
    
  } catch (e, stackTrace) {
    print('\nError during basic example:');
    print('$e');
    if (e is MurmurationException) {
      print('Error code: ${e.code}');
      if (e.originalError != null) {
        print('Original error: ${e.originalError}');
      }
    }
    print('Stack trace: $stackTrace');
  } finally {
    await murmuration.dispose();
  }
}

/// Example 2: Using Tools
Future<void> runToolExample() async {
  print('\n=== Tool Usage Example ===');
  
  final config = MurmurationConfig(
    provider: LLMProvider.openai,
    apiKey: dotenv.env['OPENAI_API_KEY']!,
    modelConfig: ModelConfig(
      modelName: 'gpt-4-turbo',
      temperature: 0.7,
      maxTokens: 1000,
    ),
  );
  
  final murmuration = Murmuration(config);
  
  try {
    // Define a simple calculator tool
    final calculatorTool = Tool(
      name: 'calculate',
      description: 'Perform a mathematical calculation',
      parameters: {
        'expression': {
          'type': 'string',
          'description': 'Mathematical expression to evaluate',
          'required': true,
        },
      },
      execute: (args) async {
        final expression = args['expression'] as String;
        // In a real app, you'd want to use a proper expression evaluator
        // This is a simplified example
        if (expression.contains('+')) {
          final parts = expression.split('+');
          return (int.parse(parts[0]) + int.parse(parts[1])).toString();
        } else if (expression.contains('*')) {
          final parts = expression.split('*');
          return (int.parse(parts[0]) * int.parse(parts[1])).toString();
        }
        throw ArgumentError('Unsupported operation');
      },
    );
    
    // Create an agent with the calculator tool
    final agent = await murmuration.createAgent(
      systemPrompt: 'You are a helpful assistant that can perform calculations. '
          'When asked to calculate something, use the calculate tool.',
      tools: [calculatorTool],
    );
    
    final prompt = 'What is 42 * 7? Show your work.';
    print('\nPrompt: $prompt');
    
    print('\nResponse:');
    
    final result = await agent.execute(prompt);
    print(result.output);
    
    if (result.toolCalls?.isNotEmpty ?? false) {
      print('\nTool calls:');
      for (final call in result.toolCalls!) {
        print('- ${call.name}(${call.arguments})');
      }
    }
    
  } catch (e, stackTrace) {
    print('\nError during tool example:');
    print('$e');
    print('Stack trace: $stackTrace');
  } finally {
    await murmuration.dispose();
  }
}

/// Example 3: Agent Chaining
Future<void> runAgentChainExample() async {
  print('\n=== Agent Chaining Example ===');
  
  final config = MurmurationConfig(
    provider: LLMProvider.anthropic,
    apiKey: dotenv.env['ANTHROPIC_API_KEY']!,
    modelConfig: ModelConfig(
      modelName: 'claude-3-opus-20240229',
      temperature: 0.7,
      maxTokens: 1000,
    ),
  );
  
  final murmuration = Murmuration(config);
  
  try {
    // Create a research agent
    final researchAgent = await murmuration.createAgent(
      systemPrompt: 'You are a research assistant. Your job is to research topics '
          'and provide detailed information. Be thorough and cite sources when possible.',
    );
    
    // Create a writing agent
    final writingAgent = await murmuration.createAgent(
      systemPrompt: 'You are a technical writer. Your job is to take research '
          'and turn it into clear, concise, and engaging content.',
    );
    
    // Create a chain of agents
    final chain = researchAgent.chain(writingAgent);
    
    final topic = 'the impact of artificial intelligence on software development';
    print('\nResearching and writing about: $topic');
    
    print('\nProcessing...');
    
    // Execute the chain
    final result = await chain.execute(
      'Research and write a 3-paragraph article about $topic',
      context: {
        'audience': 'software developers',
        'tone': 'professional but approachable',
      },
    );
    
    print('\n--- Final Article ---');
    print(result.output);
    
    print('\n--- Metadata ---');
    print('Model: ${result.model}');
    print('Tokens used: ${result.usage?.totalTokens}');
    
  } catch (e, stackTrace) {
    print('\nError during agent chain example:');
    print('$e');
    print('Stack trace: $stackTrace');
  } finally {
    await murmuration.dispose();
  }
}
