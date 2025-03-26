import 'package:flutter/material.dart'; // Importing Flutter material design package
import 'package:murmuration/murmuration.dart'; // Importing the Murmuration package for chatbot functionality
import 'package:shared_preferences/shared_preferences.dart'; // Importing shared_preferences for local storage
import 'dart:convert'; // Importing dart:convert for JSON encoding/decoding

void main() {
  runApp(const MyApp()); // Entry point of the application, runs the MyApp widget
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Murmuration Chatbot', // Title of the application
      theme: ThemeData(
        primarySwatch: Colors.blue, // Primary color theme
        visualDensity:
            VisualDensity.adaptivePlatformDensity, // Adaptive visual density
      ),
      home: const ChatScreen(), // Setting the home screen to ChatScreen
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  _ChatScreenState createState() =>
      _ChatScreenState(); // Creating the state for ChatScreen
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller =
      TextEditingController(); // Controller for the text input field
  final List<Message> _messages = []; // List to hold chat messages
  Murmuration? _murmuration; // Agent for handling chatbot interactions
  String _selectedLanguage = 'en'; // Default selected language
  String _selectedProvider = 'google'; // Default provider
  bool _isInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState(); // Calling the superclass's initState
    _initializeApp(); // Initializing the chatbot agent
  }

  Future<void> _initializeApp() async {
    try {
      await _initializeMurmuration();
      await _loadMessages();
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to initialize: $e');
      }
    }
  }

  // Method to initialize the chatbot agent
  Future<void> _initializeMurmuration() async {
    final config = MurmurationConfig(
      provider: _selectedProvider == 'google' ? LLMProvider.google : LLMProvider.openai,
      apiKey: 'your-secure-api-key',
      model: _selectedProvider == 'google' ? 'gemini-pro' : 'gpt-3.5-turbo',
    );

    _murmuration = Murmuration(config);
  }

  // Method to load saved messages from shared preferences
  Future<void> _loadMessages() async {
    try {
      final prefs = await SharedPreferences
          .getInstance(); // Getting instance of shared preferences
      final savedMessages = prefs.getStringList('chat_history') ??
          []; // Retrieving saved messages or an empty list
      if (mounted) {
        setState(() {
          _messages.addAll(savedMessages
              .map((msg) => Message.fromJson(msg))
              .toList()); // Adding loaded messages to the state
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to load messages: $e');
      }
    }
  }

  // Method to save a message to shared preferences
  Future<void> _saveMessage(Message message) async {
    try {
      final prefs = await SharedPreferences
          .getInstance(); // Getting instance of shared preferences
      final savedMessages = prefs.getStringList('chat_history') ??
          []; // Retrieving saved messages or an empty list
      savedMessages.add(message.toJson()); // Adding the new message to the list
      await prefs.setStringList('chat_history',
          savedMessages); // Saving the updated list back to shared preferences
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to save message: $e');
      }
    }
  }

  // Method to send a message
  Future<void> _sendMessage() async {
    if (_controller.text.isEmpty || _murmuration == null) return;

    final userMessage = Message(
        role: 'user',
        content: _controller.text.trim()); // Creating a user message

    setState(() {
      _messages.add(userMessage); // Adding user message to the list
      _error = null;
    });
    _controller.clear(); // Clearing the input field

    try {
      await _saveMessage(userMessage); // Saving the user message

      final agent = await _murmuration!.createAgent({
        'role': 'Assistant',
        'language': _selectedLanguage,
      });

      final result = await agent.execute(userMessage.content);
      
      if (result.stream != null) {
        String assistantResponse = '';
        await for (final chunk in result.stream!) {
          assistantResponse += chunk;
          if (mounted) {
            setState(() {
              if (_messages.last.role == 'assistant') {
                _messages.last = Message(role: 'assistant', content: assistantResponse);
              } else {
                _messages.add(Message(role: 'assistant', content: assistantResponse));
              }
            });
          }
        }
        await _saveMessage(Message(role: 'assistant', content: assistantResponse));
      } else {
        final assistantMessage = Message(
            role: 'assistant',
            content: result.output.trim()); // Creating an assistant message from the response

        if (mounted) {
          setState(() => _messages.add(assistantMessage));
        }
        await _saveMessage(assistantMessage); // Saving the assistant message
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Murmuration Chatbot'), // Title of the app bar
        actions: [
          // Provider selection dropdown
          DropdownButton<String>(
            value: _selectedProvider,
            items: const [
              DropdownMenuItem(value: 'google', child: Text('Google')),
              DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
            ],
            onChanged: (String? newValue) async {
              if (newValue != null) {
                setState(() => _selectedProvider = newValue);
                await _initializeMurmuration();
              }
            },
          ),
          const SizedBox(width: 16),
          // Language selection dropdown
          DropdownButton<String>(
            value: _selectedLanguage,
            items: const [
              DropdownMenuItem(value: 'en', child: Text('English')),
              DropdownMenuItem(value: 'es', child: Text('Spanish')),
              DropdownMenuItem(value: 'fr', child: Text('French')),
              DropdownMenuItem(value: 'de', child: Text('German')),
            ],
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() => _selectedLanguage = newValue);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              color: Colors.red[100],
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0), // Padding for the list view
              itemCount: _messages.length, // Number of messages to display
              itemBuilder: (context, index) {
                final message = _messages[
                    index]; // Getting the message at the current index
                return _buildMessageTile(message); // Building the message tile
              },
            ),
          ),
          _buildInputField(), // Building the input field for new messages
        ],
      ),
    );
  }

  // Method to build a message tile
  Widget _buildMessageTile(Message message) {
    final isUserMessage =
        message.role == 'user'; // Check if the message is from the user
    return Container(
      margin: const EdgeInsets.symmetric(
          vertical: 4.0), // Vertical margin for the message container
      padding:
          const EdgeInsets.all(10.0), // Padding inside the message container
      decoration: BoxDecoration(
        color: isUserMessage
            ? Colors.blue[100]
            : Colors.grey[200], // Background color based on message role
        borderRadius: BorderRadius.circular(
            8.0), // Rounded corners for the message container
      ),
      alignment: isUserMessage
          ? Alignment.centerRight
          : Alignment.centerLeft, // Aligning the message based on the role
      child: Column(
        crossAxisAlignment: isUserMessage
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start, // Aligning text based on message role
        children: [
          Text(
            message.role, // Displaying the role of the message
            style: TextStyle(
              fontWeight: FontWeight.bold, // Bold text for the role
              color: isUserMessage
                  ? Colors.blue
                  : Colors.black, // Color based on message role
            ),
          ),
          SizedBox(height: 4.0), // Space between role and content
          Text(
            message.content, // Displaying the content of the message
            style:
                TextStyle(fontSize: 16.0), // Font size for the message content
          ),
        ],
      ),
    );
  }

  // Method to build the input field for sending messages
  Widget _buildInputField() {
    return Padding(
      padding: const EdgeInsets.all(8.0), // Padding around the input field
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller, // Controller for the text field
              decoration: InputDecoration(
                hintText: 'Type your message...', // Placeholder text
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                      30.0), // Rounded border for the input field
                  borderSide: BorderSide(color: Colors.blue), // Border color
                ),
                filled: true, // Fill the background
                fillColor: Colors.white, // Background color of the input field
              ),
            ),
          ),
          const SizedBox(
              width: 8.0), // Space between text field and send button
          IconButton(
            icon:
                const Icon(Icons.send, color: Colors.blue), // Send button icon
            onPressed: _sendMessage, // Action to perform on button press
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _murmuration?.dispose();
    super.dispose();
  }
}

// Message class to represent a chat message
class Message {
  final String role; // Role of the message sender (user or assistant)
  final String content; // Content of the message

  const Message({required this.role, required this.content}); // Constructor for Message

  // Method to convert Message to JSON string
  String toJson() => jsonEncode({
        'role': role,
        'content': content,
      });

  // Static method to create a Message from a JSON string
  static Message fromJson(String json) {
    final data = jsonDecode(json);
    return Message(
      role: data['role'],
      content: data['content'],
    );
  }
}
