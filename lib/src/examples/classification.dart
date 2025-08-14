import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:murmuration/murmuration.dart';

void main() {
  WidgetsFlutterBinding
      .ensureInitialized(); // Ensures that Flutter is initialized before running the app
  runApp(const MurmurationTextClassifier()); // Running the main app widget
}

class MurmurationTextClassifier extends StatelessWidget {
  const MurmurationTextClassifier({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Murmuration Text Classifier', // Title of the application
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue), // Color scheme based on a seed color
        useMaterial3: true, // Enabling Material 3 design
      ),
      home: const ClassifierHome(), // Setting the home screen to ClassifierHome
    );
  }
}

// Class for handling text classification using Murmuration
class TextClassifier {
  final Murmuration _murmuration;
  static const String _threadId = 'text_classification';
  final String _provider;
  
  // Cache for classification results
  final Map<String, Map<String, dynamic>> _cache = {};

  TextClassifier(String apiKey, {String provider = 'anthropic'})
      : _provider = provider,
        _murmuration = Murmuration(
          MurmurationConfig(
            provider: _getProviderFromString(provider),
            apiKey: apiKey,
            modelConfig: ModelConfig(
              modelName: _getModelForProvider(provider),
              temperature: 0.2, // Lower temperature for more consistent classifications
              maxTokens: 1000,
            ),
            cacheConfig: const CacheConfig(
              enabled: true,
              ttl: Duration(hours: 1),
            ),
            debug: true,
            threadId: _threadId,
            maxRetries: 3,
            retryDelay: const Duration(seconds: 1),
          ),
        );
        
  static LLMProvider _getProviderFromString(String provider) {
    switch (provider) {
      case 'anthropic':
        return LLMProvider.anthropic;
      case 'openai':
        return LLMProvider.openai;
      case 'google':
        return LLMProvider.google;
      default:
        return LLMProvider.anthropic;
    }
  }
  
  static String _getModelForProvider(String provider) {
    switch (provider) {
      case 'anthropic':
        return 'claude-3-haiku-20240307';
      case 'openai':
        return 'gpt-4-turbo';
      case 'google':
        return 'gemini-pro';
      default:
        return 'claude-3-haiku-20240307';
    }
  }

  /// Classify text with streaming support
  Stream<Map<String, dynamic>> classifyStream(String text) async* {
    if (text.isEmpty) {
      throw ArgumentError('Input text cannot be empty');
    }
    
    // Check cache first
    final cacheKey = '${_provider}_${text.hashCode}';
    if (_cache.containsKey(cacheKey)) {
      yield _cache[cacheKey]!;
      return;
    }

    try {
      final agent = await _murmuration.createAgent(
        systemPrompt: '''You are a text classification expert. Analyze the given text and provide your analysis in this exact JSON format:
{
  "sentiment": ["positive", "neutral", or "negative"],
  "aggressiveness": [number between 1-5],
  "language": ["spanish", "english", "french", "german", or "italian"],
  "key_phrases": ["list", "of", "key", "phrases"],
  "confidence": [number between 0-1]
}
Important: Return ONLY the JSON object, no other text.''',
      );

      String fullResponse = '';
      final stream = agent.executeStream(text);
      
      await for (final chunk in stream) {
        if (!chunk.isDone) {
          fullResponse += chunk.content;
          
          // Try to parse the partial response
          try {
            final cleanOutput = _cleanJsonOutput(fullResponse);
            final parsedOutput = json.decode(cleanOutput) as Map<String, dynamic>;
            _processParsedOutput(parsedOutput);
            _cache[cacheKey] = parsedOutput;
            yield parsedOutput;
          } catch (e) {
            // Ignore parsing errors for partial responses
          }
        }
      }
      
      // Final parse to ensure we have valid output
      final cleanOutput = _cleanJsonOutput(fullResponse);
      final parsedOutput = json.decode(cleanOutput) as Map<String, dynamic>;
      _processParsedOutput(parsedOutput);
      _cache[cacheKey] = parsedOutput;
      yield parsedOutput;
      
    } catch (e) {
      if (e is FormatException) {
        throw Exception('Failed to parse AI response: ${e.message}');
      }
      throw Exception('Classification failed: $e');
    }
  }
  
  /// Classify text with a single response
  Future<Map<String, dynamic>> classify(String text) async {
    final stream = classifyStream(text);
    Map<String, dynamic>? result;
    
    await for (final value in stream) {
      result = value;
    }
    
    return result ?? {
      'sentiment': 'neutral',
      'aggressiveness': 1,
      'language': 'unknown',
      'key_phrases': [],
      'confidence': 0,
    };
  }
  
  void _processParsedOutput(Map<String, dynamic> output) {
    // Ensure all required fields exist with defaults
    output['sentiment'] ??= 'neutral';
    
    // Process aggressiveness (1-5)
    if (output['aggressiveness'] is String) {
      output['aggressiveness'] = int.tryParse(output['aggressiveness']) ?? 1;
    }
    output['aggressiveness'] = (output['aggressiveness'] as num? ?? 1)
        .clamp(1, 5)
        .toInt();
        
    // Ensure language is valid
    const validLanguages = {'spanish', 'english', 'french', 'german', 'italian'};
    if (!validLanguages.contains(output['language']?.toString().toLowerCase())) {
      output['language'] = 'unknown';
    }
    
    // Ensure key_phrases is a List<String>
    if (output['key_phrases'] is! List) {
      output['key_phrases'] = [];
    } else {
      output['key_phrases'] = (output['key_phrases'] as List)
          .whereType<String>()
          .toList();
    }
    
    // Ensure confidence is a double between 0-1
    if (output['confidence'] is String) {
      output['confidence'] = double.tryParse(output['confidence']) ?? 0.5;
    }
    output['confidence'] = (output['confidence'] as num? ?? 0.5)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  String _cleanJsonOutput(String output) {
    String cleanOutput = output.trim();
    
    // Remove code block markers
    const jsonStartMarkers = ['```json', '```JSON', '```'];
    for (final marker in jsonStartMarkers) {
      if (cleanOutput.startsWith(marker)) {
        cleanOutput = cleanOutput.substring(marker.length).trimLeft();
        break;
      }
    }
    
    // Remove trailing code block markers
    const jsonEndMarkers = ['```'];
    for (final marker in jsonEndMarkers) {
      if (cleanOutput.endsWith(marker)) {
        cleanOutput = cleanOutput.substring(0, cleanOutput.length - marker.length).trimRight();
        break;
      }
    }
    if (cleanOutput.endsWith('```')) {
      cleanOutput = cleanOutput.substring(0, cleanOutput.length - 3);
    }
    return cleanOutput.trim();
  }

  // Method to clear the classification history
  Future<void> clearHistory() async {
    await _murmuration.clearHistory(
        _threadId); // Clearing history for the specified thread ID
  }

  void dispose() {
    _murmuration.dispose();
  }
}

// Home screen for the classifier application
class ClassifierHome extends StatelessWidget {
  const ClassifierHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Murmuration Text Classifier'), // Title of the app bar
        backgroundColor: Theme.of(context)
            .colorScheme
            .primaryContainer, // App bar background color
      ),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16.0), // Padding for the scroll view
          child: ClassificationWidget(), // Including the classification widget
        ),
      ),
    );
  }
}

// Widget for text classification input and results
class ClassificationWidget extends StatefulWidget {
  const ClassificationWidget({super.key});

  @override
  State<ClassificationWidget> createState() =>
      _ClassificationWidgetState(); // Creating the state for the widget
}

class _ClassificationWidgetState extends State<ClassificationWidget> {
  final TextEditingController _textController =
      TextEditingController(); // Controller for the text input field
  late TextClassifier _classifier;
  Map<String, dynamic>?
      _classification; // Variable to hold classification results
  bool _isLoading = false; // Loading state for the classification process
  String? _error; // Variable to hold error messages
  String _selectedProvider = 'google';

  @override
  void initState() {
    super.initState();
    _initializeClassifier();
  }

  void _initializeClassifier() {
    _classifier = TextClassifier(
      'your-secure-api-key',
      provider: _selectedProvider,
    );
  }

  @override
  void dispose() {
    _textController.dispose(); // Disposing the text controller
    _classifier.dispose();
    super.dispose(); // Calling the superclass dispose method
  }

  // Method to classify the text input
  Future<void> _classifyText() async {
    if (_textController.text.isEmpty) {
      setState(() => _error =
          'Please enter some text to classify'); // Error if input is empty
      return;
    }

    setState(() {
      _isLoading = true; // Setting loading state
      _error = null; // Clearing any previous error
    });

    try {
      final classification = await _classifier
          .classify(_textController.text); // Classifying the input text

      if (mounted) {
        setState(() {
          _classification = classification; // Storing the classification result
          _isLoading = false; // Resetting loading state
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString(); // Storing error message
          _isLoading = false; // Resetting loading state
        });
      }
    }
  }

  // Method to build the result card displaying classification results
  Widget _buildResultCard() {
    if (_error != null) {
      return Card(
        color: Theme.of(context)
            .colorScheme
            .errorContainer, // Card color for error
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!, // Displaying the error message
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onErrorContainer, // Text color for error
            ),
    return Card(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _isLoading && _classification == null
            ? const Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? _buildErrorCard()
                : _classification == null
                    ? _buildEmptyState()
                    : _buildResultContent(),
      ),
    );
  }

  Widget _buildErrorCard() {
    return ListTile(
      leading: const Icon(Icons.error_outline, color: Colors.red),
      title: const Text('Error', style: TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(_error ?? 'An unknown error occurred'),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => setState(() => _error = null),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Enter text to analyze',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          Text(
            'The AI will analyze sentiment, language, and more',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildResultContent() {
    final confidence = _classification?['confidence'] as double? ?? 0.0;
    final keyPhrases = _classification?['key_phrases'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Provider and confidence header
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Provider selector
              DropdownButton<String>(
                value: _selectedProvider,
                items: const [
                  DropdownMenuItem(value: 'google', child: Text('Google')),
                  DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                ],
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedProvider = newValue;
                      _initializeClassifier();
                    });
                  }
                },
                underline: const SizedBox(),
                isDense: true,
              ),
              const Spacer(),
              // Confidence indicator
              if (confidence > 0)
                Row(
                  children: [
                    Text(
                      '${(confidence * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      confidence > 0.8
                          ? Icons.verified
                          : confidence > 0.5
                              ? Icons.info_outline
                              : Icons.warning_amber,
                      size: 16,
                      color: confidence > 0.8
                          ? Colors.green
                          : confidence > 0.5
                              ? Colors.orange
                              : Colors.red,
                    ),
                  ],
                ),
            ],
          ),
        ),

        // Main result sections
        _buildResultSection(
          icon: Icons.sentiment_satisfied,
          title: 'Sentiment',
          value: _classification!['sentiment']?.toString().toUpperCase() ?? 'N/A',
          color: _getSentimentColor(_classification!['sentiment']),
        ),

        _buildResultSection(
          icon: Icons.whatshot,
          title: 'Aggressiveness',
          value: _buildAggressivenessIndicator(_classification!['aggressiveness'] as int? ?? 1),
        ),

        _buildResultSection(
          icon: Icons.language,
          title: 'Language',
          value: _classification!['language']?.toString().toUpperCase() ?? 'N/A',
        ),

        // Key phrases section
        if (keyPhrases.isNotEmpty) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Key Phrases',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: keyPhrases
                      .take(10)
                      .map((phrase) => Chip(
                            label: Text(
                              phrase.toString(),
                              style: const TextStyle(fontSize: 12),
                            ),
                            backgroundColor: Colors.blue[50],
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        ],

        // Raw JSON toggle
        Padding(
          padding: const EdgeInsets.only(top: 8.0, right: 8.0, bottom: 8.0),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Raw Analysis'),
                    content: SingleChildScrollView(
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert(_classification),
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.code, size: 16),
              label: const Text('View Raw Data'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultSection({
    required IconData icon,
    required String title,
    required String value,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAggressivenessIndicator(int level) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < level ? Icons.whatshot : Icons.whatshot_outlined,
          color: index < level ? Colors.orange : Colors.grey[300],
          size: 20,
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Input card
        Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _textController,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: 'Enter text to analyze',
                    hintText: 'Paste or type any text content here...',
                    border: const OutlineInputBorder(),
                    suffixIcon: _textController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _textController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _textController.text.trim().isEmpty || _isLoading
                            ? null
                            : _classifyText,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.analytics, size: 20),
                        label: Text(_isLoading ? 'Analyzing...' : 'Analyze Text'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Results section
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _classification != null || _error != null || _isLoading
                ? _buildResultCard()
                : _buildEmptyState(),
          ),
        ),
      ],
    );
  }
}
