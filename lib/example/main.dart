import 'package:flutter/material.dart';
import '../murmuration.dart';

void main() {
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('Flutter Error: ${details.exception}');
  };

  runApp(const MurmurationApp());
}

class MurmurationApp extends StatelessWidget {
  const MurmurationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Murmuration Agents Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MurmurationDemo(),
    );
  }
}

class MurmurationDemo extends StatefulWidget {
  const MurmurationDemo({super.key});

  @override
  State<MurmurationDemo> createState() => _MurmurationDemoState();
}

class _MurmurationDemoState extends State<MurmurationDemo> {
  final TextEditingController _outputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  final List<String> _logMessages = [];
  bool _isProcessing = false;

  void _appendOutput(String text, {bool isError = false}) {
    if (!mounted) return;

    final timestamp = DateTime.now().toString().split('.').first;
    final formattedText = '[$timestamp] ${isError ? '❌ ' : ''}$text\n';

    setState(() {
      _logMessages.add(formattedText);
      _outputController.text = _logMessages.join('');
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _runChainedAgents() async {
    if (_isProcessing) return;

    final userInput = _inputController.text.trim();
    if (userInput.isEmpty) {
      _appendOutput('Please enter a math expression to process', isError: true);
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final client = Murmuration(
        MurmurationConfig(
          apiKey: 'enter-your-api-key-here',
          model: 'gemini-1.5-flash-latest',
          debug: true,
          stream: false,
          logger: MurmurationLogger(
            enabled: true,
            onLog: (message) => _appendOutput('📝 $message'),
            onError: (error) => _appendOutput(error, isError: true),
          ),
        ),
      );

      _appendOutput('🚀 Starting agent chain...');

      final agentInstructions = [
        {
          'role': '''You are a math processing agent. Your job is to:
                    1. Parse the mathematical expression
                    2. Use the calculator tool to compute the result
                    3. Pass the result to the next agent''',
        },
        {
          'role': '''You are an explanation agent. Your job is to:
                    1. Take the mathematical result
                    2. Provide a clear, step-by-step explanation of how we got there
                    3. Use simple language that's easy to understand''',
        },
        {
          'role': '''You are a translation agent. Your job is to:
                    1. Take the explanation
                    2. Translate it to Spanish
                    3. Maintain mathematical accuracy in the translation
                    4. Keep the same clear, educational tone''',
        },
      ];

      final calculator = MurmurationTool(
        name: 'calculator',
        description: 'Performs basic math operations',
        schema: {
          'type': 'object',
          'properties': {
            'operation': {'type': 'string'},
            'numbers': {
              'type': 'array',
              'items': {'type': 'number'}
            },
          },
        },
        execute: (Map<String, dynamic> params) {
          final numbers = params['numbers'] as List<num>;
          switch (params['operation']) {
            case 'add':
              return numbers.reduce((a, b) => a + b);
            case 'multiply':
              return numbers.reduce((a, b) => a * b);
            case 'subtract':
              return numbers.reduce((a, b) => a - b);
            case 'divide':
              return numbers.reduce((a, b) => a / b);
            default:
              throw MurmurationError('Unknown operation');
          }
        },
      );

      final result = await client.runAgentChain(
        input: userInput,
        agentInstructions: agentInstructions,
        tools: [calculator],
        logProgress: true,
        onProgress: (progress) {
          final emoji = progress.status.contains('error') ? '❌' : '🔄';
          _appendOutput(
            '$emoji Agent ${progress.currentAgent}/${progress.totalAgents}: ${progress.status}' +
                (progress.output != null ? '\n   └─ ${progress.output}' : ''),
          );
        },
      );

      _appendOutput('\n✨ Chain completed!');
      _appendOutput('📊 Final output: ${result.finalOutput}');

      if (result.results.any((r) => r.stream != null)) {
        for (final agentResult in result.results) {
          if (agentResult.stream != null) {
            await for (final chunk in agentResult.stream!) {
              _appendOutput('🔄 Streaming: $chunk');
            }
          }
        }
      }
    } catch (e, stackTrace) {
      _appendOutput('Error occurred: $e', isError: true);
      debugPrint('Stack trace: $stackTrace');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Murmuration Agent Chain Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _inputController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Enter a math expression (e.g., "5 + 3 * 2")',
                hintText: 'Enter your expression here...',
              ),
              enabled: !_isProcessing,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: _outputController,
                  scrollController: _scrollController,
                  maxLines: null,
                  readOnly: true,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.all(16),
                    border: InputBorder.none,
                    hintText: 'Agent outputs will appear here...',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _runChainedAgents,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_isProcessing ? 'Processing...' : 'Run Agents'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _logMessages.clear();
                      _outputController.clear();
                    });
                  },
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear Log'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _outputController.dispose();
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }
}
