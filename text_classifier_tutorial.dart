<!DOCTYPE html>
<html lang="en">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Building a Text Classifier with Murmuration and Flutter 🐦✨</title>
    <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700&display=swap" rel="stylesheet">
    <style>
        body {
            margin: 0;
            font-family: 'Roboto', sans-serif;
            background: linear-gradient(to bottom, #0175C2, #1E1E1E);
            color: #ECEFF1;
        }

        header {
            background: #02569B;
            padding: 20px;
            text-align: center;
            box-shadow: 0px 4px 6px rgba(0, 0, 0, 0.2);
        }

        header h1 {
            font-size: 2.5rem;
            margin: 0;
            color: #FFFFFF;
        }

        .content {
            max-width: 800px;
            margin: 20px auto;
            padding: 20px;
            background: #263238;
            border-radius: 10px;
            box-shadow: 0px 6px 10px rgba(0, 0, 0, 0.3);
            text-align: left;
        }

        .content h2 {
            color: #0288D1;
            border-bottom: 2px solid #0288D1;
            padding-bottom: 5px;
        }

        .code-block {
            background: #37474F;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
        }

        .code-block pre {
            margin: 0;
            color: #ECEFF1;
        }

        footer {
            text-align: center;
            padding: 10px;
            background: #02569B;
            margin-top: 20px;
            color: #B3E5FC;
        }
    </style>
</head>

<body>
    <header>
        <h1>Building a Text Classifier with Murmuration and Flutter 🐦✨</h1>
    </header>

    <div class="content">
        <h2>Introduction</h2>
        <p>In this tutorial, we will create a text classification application using the Murmuration framework and Flutter. This application will allow users to input text and receive classifications based on sentiment, aggressiveness, and language. We will utilize the Murmuration framework's AI capabilities to analyze the text.</p>

        <h2>Prerequisites</h2>
        <ul>
            <li>Flutter SDK installed on your machine.</li>
            <li>A basic understanding of Dart and Flutter.</li>
            <li>An API key for the Murmuration framework.</li>
        </ul>

        <h2>Step 1: Setting Up Your Flutter Project</h2>
        <ol>
            <li><strong>Create a new Flutter project:</strong>
                <pre>flutter create murmuration_text_classifier
cd murmuration_text_classifier</pre>
            </li>
            <li><strong>Add dependencies:</strong> Open <code>pubspec.yaml</code> and add the following dependencies:
                <div class="code-block">
                    <pre>dependencies:
  flutter:
    sdk: flutter
  murmuration: ^latest_version</pre>
                </div>
            </li>
            <li><strong>Install the dependencies:</strong>
                <pre>flutter pub get</pre>
            </li>
        </ol>

        <h2>Step 2: Building the Text Classifier Application</h2>

        <h3>2.1 Main Application Entry Point</h3>
        <p>In <code>lib/main.dart</code>, we will set up the main entry point of our application:</p>
        <div class="code-block">
            <pre>import 'package:flutter/material.dart';
import 'package:murmuration/murmuration.dart';
import 'dart:convert';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MurmurationTextClassifier());
}

class MurmurationTextClassifier extends StatelessWidget {
  const MurmurationTextClassifier({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Murmuration Text Classifier',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ClassifierHome(),
    );
  }
}</pre>
        </div>

        <h3>2.2 Creating the Text Classifier Logic</h3>
        <p>Next, we will create the logic for handling text classification using the Murmuration framework:</p>
        <div class="code-block">
            <pre>class TextClassifier {
  final Murmuration _murmuration;
  static const String _threadId = 'text_classification';

  TextClassifier(String apiKey)
      : _murmuration = Murmuration(
          MurmurationConfig(
            apiKey: apiKey,
            debug: true,
            threadId: _threadId,
            maxRetries: 3,
            retryDelay: const Duration(seconds: 1),
          ),
        );

  Future<Map<String, dynamic>> classify(String text) async {
    try {
      final agent = await _murmuration.createAgent({
        'role': '''You are a text classification expert. Analyze the given text and provide your analysis in this exact JSON format:
{
  "sentiment": ["happy", "neutral", or "sad"],
  "aggressiveness": [number between 1-5],
  "language": ["spanish", "english", "french", "german", or "italian"]
}
Important: Return ONLY the JSON object, no other text.''',
      });

      final result = await agent.execute(text);
      String cleanOutput = result.output.trim();
      if (cleanOutput.startsWith('```json')) {
        cleanOutput = cleanOutput.substring(7);
      }
      if (cleanOutput.endsWith('```')) {
        cleanOutput = cleanOutput.substring(0, cleanOutput.length - 3);
      }
      cleanOutput = cleanOutput.trim();

      final Map<String, dynamic> parsedOutput = json.decode(cleanOutput);
      if (parsedOutput['aggressiveness'] is String) {
        parsedOutput['aggressiveness'] = int.parse(parsedOutput['aggressiveness']);
      }

      return parsedOutput;
    } catch (e) {
      if (e is FormatException) {
        throw Exception('Failed to parse AI response: ${e.message}');
      }
      throw Exception('Classification failed: $e');
    }
  }

  Future<void> clearHistory() async {
    await _murmuration.clearHistory(_threadId);
  }
}</pre>
        </div>

        <h3>2.3 Creating the Home Screen</h3>
        <p>Now, we will create the home screen for our text classifier application:</p>
        <div class="code-block">
            <pre>class ClassifierHome extends StatelessWidget {
  const ClassifierHome({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Murmuration Text Classifier'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16.0),
          child: ClassificationWidget(),
        ),
      ),
    );
  }
}</pre>
        </div>

        <h3>2.4 Building the Classification Widget</h3>
        <p>Finally, we will create the widget that handles user input and displays classification results:</p>
        <div class="code-block">
            <pre>class ClassificationWidget extends StatefulWidget {
  const ClassificationWidget({Key? key}) : super(key: key);

  @override
  State<ClassificationWidget> createState() => _ClassificationWidgetState();
}

class _ClassificationWidgetState extends State<ClassificationWidget> {
  final TextEditingController _textController = TextEditingController();
  final TextClassifier _classifier = TextClassifier('your-api-key');
  Map<String, dynamic>? _classification;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _classifyText() async {
    if (_textController.text.isEmpty) {
      setState(() => _error = 'Please enter some text to classify');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final classification = await _classifier.classify(_textController.text);
      if (mounted) {
        setState(() {
          _classification = classification;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildResultCard() {
    if (_error != null) {
      return Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
      );
    }

    if (_classification == null) {
      return const SizedBox.shrink();
    }

    Color sentimentColor;
    switch (_classification!['sentiment']) {
      case 'happy':
        sentimentColor = Colors.green;
        break;
      case 'sad':
        sentimentColor = Colors.red;
        break;
      default:
        sentimentColor = Colors.blue;
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Classification Results',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.emoji_emotions, color: sentimentColor),
                const SizedBox(width: 8),
                Text(
                  'Sentiment: ${_classification!['sentiment']}',
                  style: TextStyle(color: sentimentColor),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.warning_amber),
                const SizedBox(width: 8),
                Text(
                  'Aggressiveness: ${_classification!['aggressiveness']}/5',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.language),
                const SizedBox(width: 8),
                Text(
                  'Language: ${_classification!['language']}',
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _textController,
          decoration: InputDecoration(
            labelText: 'Enter text to classify',
            hintText: 'Type or paste your text here...',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _textController.clear();
                setState(() {
                  _classification = null;
                  _error = null;
                });
              },
            ),
          ),
          maxLines: 4,
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _classifyText,
          icon: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.psychology),
          label: Text(_isLoading ? 'Classifying...' : 'Classify Text'),
        ),
        const SizedBox(height: 16),
        _buildResultCard(),
      ],
    );
  }
}</pre>
        </div>

        <h2>Conclusion</h2>
        <p>Congratulations! You have successfully built a text classification application using the Murmuration framework and Flutter. This application allows users to input text and receive classifications based on sentiment, aggressiveness, and language.</p>
        <p>Feel free to expand upon this example by adding more features, such as additional classification categories, user authentication, or integrating other APIs.</p>
    </div>

    <footer>
        <p>Created by <strong>Agniva Maiti</strong> © 2025.</p>
    </footer>
</body>

</html>
