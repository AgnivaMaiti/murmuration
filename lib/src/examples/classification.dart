import 'package:flutter/material.dart'; // Importing Flutter's material design package
import 'package:murmuration/murmuration.dart'; // Importing Murmuration package for AI functionalities
import 'dart:convert'; // Importing dart:convert for JSON encoding/decoding

void main() {
  WidgetsFlutterBinding
      .ensureInitialized(); // Ensures that Flutter is initialized before running the app
  runApp(const MurmurationTextClassifier()); // Running the main app widget
}

class MurmurationTextClassifier extends StatelessWidget {
  const MurmurationTextClassifier({Key? key})
      : super(key: key); // Constructor for the main app widget

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
  TextClassifier(String apiKey)
      : _murmuration = Murmuration(
          MurmurationConfig(
            apiKey: apiKey, // API key for authentication
            debug: true, // Enable debug mode
            threadId: _threadId, // Setting the thread ID
            maxRetries: 3, // Maximum number of retries for requests
            retryDelay: const Duration(seconds: 1), // Delay between retries
          ),
        );

  // Method to classify the given text
  Future<Map<String, dynamic>> classify(String text) async {
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

      // Clean and parse the output
      String cleanOutput = result.output.trim(); // Trimming the output
      if (cleanOutput.startsWith('```json')) {
        cleanOutput =
            cleanOutput.substring(7); // Removing the JSON code block prefix
      }
      if (cleanOutput.endsWith('```')) {
        cleanOutput = cleanOutput.substring(
            0, cleanOutput.length - 3); // Removing the code block suffix
      }
      cleanOutput = cleanOutput.trim(); // Final trim

      // Parse the JSON
      final Map<String, dynamic> parsedOutput =
          json.decode(cleanOutput); // Decoding the JSON string

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

  // Method to clear the classification history
  Future<void> clearHistory() async {
    await _murmuration.clearHistory(
        _threadId); // Clearing history for the specified thread ID
  }
}

// Home screen for the classifier application
class ClassifierHome extends StatelessWidget {
  const ClassifierHome({Key? key})
      : super(key: key); // Constructor for ClassifierHome

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
  const ClassificationWidget({Key? key})
      : super(key: key); // Constructor for ClassificationWidget

  @override
  State<ClassificationWidget> createState() =>
      _ClassificationWidgetState(); // Creating the state for the widget
}

class _ClassificationWidgetState extends State<ClassificationWidget> {
  final TextEditingController _textController =
      TextEditingController(); // Controller for the text input field
  final TextClassifier _classifier = TextClassifier(
    'your-api-key', // Replace with your API key
  );
  Map<String, dynamic>?
      _classification; // Variable to hold classification results
  bool _isLoading = false; // Loading state for the classification process
  String? _error; // Variable to hold error messages

  @override
  void dispose() {
    _textController.dispose(); // Disposing the text controller
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

    Color sentimentColor; // Variable to hold sentiment color
    switch (_classification!['sentiment']) {
      case 'happy':
        sentimentColor = Colors.green; // Green for happy sentiment
        break;
      case 'sad':
        sentimentColor = Colors.red; // Red for sad sentiment
        break;
      default:
        sentimentColor = Colors.blue; // Blue for neutral sentiment
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
            Row(
              children: [
                Icon(Icons.emoji_emotions,
                    color: sentimentColor), // Icon for sentiment
                const SizedBox(width: 8), // Space between icon and text
                Text(
                  'Sentiment: ${_classification!['sentiment']}', // Displaying sentiment
                  style: TextStyle(
                      color: sentimentColor), // Text color based on sentiment
                ),
              ],
            ),
            const SizedBox(
                height: 16), // Space between sentiment and aggressiveness
            Row(
              children: [
                const Icon(Icons.warning_amber), // Icon for aggressiveness
                const SizedBox(width: 8), // Space between icon and text
                Text(
                  'Aggressiveness: ${_classification!['aggressiveness']}/5', // Displaying aggressiveness
                ),
              ],
            ),
            const SizedBox(
                height: 8), // Space between aggressiveness and language
            Row(
              children: [
                const Icon(Icons.language), // Icon for language
                const SizedBox(width: 8), // Space between icon and text
                Text(
                  'Language: ${_classification!['language']}', // Displaying detected language
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment
          .stretch, // Stretching the column to fill available width
      children: [
        TextField(
          controller: _textController, // Controller for the text field
          decoration: InputDecoration(
            labelText: 'Enter text to classify', // Label for the text field
            hintText:
                'Type or paste your text here...', // Hint text for the text field
            border:
                const OutlineInputBorder(), // Border style for the text field
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear), // Clear icon button
              onPressed: () {
                _textController.clear(); // Clearing the text field
                setState(() {
                  _classification = null; // Resetting classification result
                  _error = null; // Resetting error message
                });
              },
            ),
          ),
          maxLines: 4, // Allowing multiple lines in the text field
        ),
        const SizedBox(height: 16), // Space between text field and button
        ElevatedButton.icon(
          onPressed:
              _isLoading ? null : _classifyText, // Disabling button if loading
          icon: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2), // Loading indicator
                )
              : const Icon(Icons.psychology), // Icon for classify button
          label: Text(
              _isLoading ? 'Classifying...' : 'Classify Text'), // Button label
        ),
        const SizedBox(height: 16), // Space between button and result card
        _buildResultCard(), // Building the result card to display classification results
      ],
    );
  }
}
