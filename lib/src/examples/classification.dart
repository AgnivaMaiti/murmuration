import 'package:flutter/material.dart'; // Importing Flutter's material design package
import 'package:murmuration/murmuration.dart'; // Importing Murmuration package for AI functionalities
import 'dart:convert'; // Importing dart:convert for JSON encoding/decoding

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
  final Murmuration _murmuration; // Instance of Murmuration for AI interactions
  static const String _threadId =
      'text_classification'; // Thread ID for classification tasks

  // Constructor for TextClassifier, initializes Murmuration with API key and settings
  TextClassifier(String apiKey, {String provider = 'google'})
      : _murmuration = Murmuration(
          MurmurationConfig(
            provider:
                provider == 'google' ? LLMProvider.google : LLMProvider.openai,
            apiKey: apiKey,
            modelConfig: ModelConfig(
              modelName: provider == 'google' ? 'gemini-pro' : 'gpt-3.5-turbo',
            ),
            debug: true,
            threadId: _threadId,
            maxRetries: 3,
            retryDelay: const Duration(seconds: 1),
          ),
        );

  // Method to classify the given text
  Future<Map<String, dynamic>> classify(String text) async {
    if (text.isEmpty) {
      throw Exception('Input text cannot be empty');
    }

    try {
      // Creating an agent with a specific role for text classification
      final agent = await _murmuration.createAgent({
        'role':
            '''You are a text classification expert. Analyze the given text and provide your analysis in this exact JSON format:
{
  "sentiment": ["happy", "neutral", or "sad"],
  "aggressiveness": [number between 1-5],
  "language": ["spanish", "english", "french", "german", or "italian"]
}
Important: Return ONLY the JSON object, no other text.''',
      });

      final result =
          await agent.execute(text); // Executing the agent with the input text

      final cleanOutput = _cleanJsonOutput(result.output);
      final parsedOutput = json.decode(cleanOutput) as Map<String, dynamic>;

      // Convert numeric strings to integers if needed
      if (parsedOutput['aggressiveness'] is String) {
        parsedOutput['aggressiveness'] = int.parse(parsedOutput[
            'aggressiveness']); // Parsing aggressiveness to integer
      }

      return parsedOutput; // Returning the parsed output
    } catch (e) {
      if (e is FormatException) {
        throw Exception(
            'Failed to parse AI response: ${e.message}'); // Handling format exceptions
      }
      throw Exception(
          'Classification failed: $e'); // General classification failure
    }
  }

  String _cleanJsonOutput(String output) {
    String cleanOutput = output.trim();
    if (cleanOutput.startsWith('```json')) {
      cleanOutput = cleanOutput.substring(7);
    }
    if (cleanOutput.startsWith('```')) {
      cleanOutput = cleanOutput.substring(3);
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
          ),
        ),
      );
    }

    if (_classification == null) {
      return const SizedBox
          .shrink(); // Return empty widget if no classification
    }

    return Card(
      elevation: 2, // Elevation for the card
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start, // Aligning children to the start
          children: [
            Text(
              'Classification Results', // Title for the results
              style: Theme.of(context)
                  .textTheme
                  .titleLarge, // Styling for the title
            ),
            const SizedBox(height: 16), // Space between title and results
            _buildResultRow(
              icon: Icons.emoji_emotions,
              label: 'Sentiment',
              value: _classification!['sentiment'],
              color: _getSentimentColor(_classification!['sentiment']),
            ),
            const SizedBox(
                height: 8), // Space between sentiment and aggressiveness
            _buildResultRow(
              icon: Icons.speed,
              label: 'Aggressiveness',
              value: '${_classification!['aggressiveness']}/5',
            ),
            const SizedBox(
                height: 8), // Space between aggressiveness and language
            _buildResultRow(
              icon: Icons.language,
              label: 'Language',
              value: _classification!['language'],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow({
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Text(
          '$label: $value',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Color _getSentimentColor(String sentiment) {
    switch (sentiment) {
      case 'happy':
        return Colors.green;
      case 'sad':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment
          .stretch, // Stretching the column to fill available width
      children: [
        // Provider selection dropdown
        DropdownButtonFormField<String>(
          value: _selectedProvider,
          decoration: const InputDecoration(
            labelText: 'Select Provider',
            border: OutlineInputBorder(),
          ),
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
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _textController, // Controller for the text field
          maxLines: 5,
          decoration: InputDecoration(
            labelText: 'Enter text to classify', // Label for the text field
            border: OutlineInputBorder(), // Border for the text field
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _isLoading ? null : _classifyText,
          child: _isLoading
              ? const CircularProgressIndicator()
              : const Text('Classify'),
        ),
        const SizedBox(height: 16),
        _buildResultCard(), // Display results if available
      ],
    );
  }
}
