import 'package:flutter/material.dart'; // Importing Flutter material design package
import 'package:murmuration/murmuration.dart'; // Importing the Murmuration package for chatbot functionality
import 'package:shared_preferences/shared_preferences.dart'; // Importing shared_preferences for local storage
import 'dart:convert'; // Importing dart:convert for JSON encoding/decoding

void main() {
  runApp(MyApp()); // Entry point of the application, runs the MyApp widget
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Murmuration Chatbot', // Title of the application
      theme: ThemeData(
        primarySwatch: Colors.blue, // Primary color theme
        visualDensity:
            VisualDensity.adaptivePlatformDensity, // Adaptive visual density
      ),
      home: ChatScreen(), // Setting the home screen to ChatScreen
    );
  }
}

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() =>
      _ChatScreenState(); // Creating the state for ChatScreen
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller =
      TextEditingController(); // Controller for the text input field
  final List<Message> _messages = []; // List to hold chat messages
  late Agent _agent; // Agent for handling chatbot interactions
  String _selectedLanguage = 'en'; // Default selected language

  @override
  void initState() {
    super.initState(); // Calling the superclass's initState
    _initializeAgent(); // Initializing the chatbot agent
    _loadMessages(); // Loading saved messages from local storage
  }

  // Method to initialize the chatbot agent
  Future<void> _initializeAgent() async {
    final config = MurmurationConfig(
        apiKey: 'add-your-api-key'); // Configuration for the agent
    _agent = await Murmuration(config).createAgent({
      // Creating the agent with specified role and language
      'role': 'Assistant',
      'language': _selectedLanguage,
    });
  }

  // Method to load saved messages from shared preferences
  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences
        .getInstance(); // Getting instance of shared preferences
    final savedMessages = prefs.getStringList('chat_history') ??
        []; // Retrieving saved messages or an empty list
    setState(() {
      _messages.addAll(savedMessages
          .map((msg) => Message.fromJson(msg))
          .toList()); // Adding loaded messages to the state
    });
  }

  // Method to save a message to shared preferences
  Future<void> _saveMessage(Message message) async {
    final prefs = await SharedPreferences
        .getInstance(); // Getting instance of shared preferences
    final savedMessages = prefs.getStringList('chat_history') ??
        []; // Retrieving saved messages or an empty list
    savedMessages.add(message.toJson()); // Adding the new message to the list
    await prefs.setStringList('chat_history',
        savedMessages); // Saving the updated list back to shared preferences
  }

  // Method to send a message
  Future<void> _sendMessage() async {
    if (_controller.text.isEmpty) return; // Return if the input is empty

    final userMessage = Message(
        role: 'user', content: _controller.text); // Creating a user message
    setState(() {
      _messages.add(userMessage); // Adding user message to the list
    });
    _controller.clear(); // Clearing the input field

    await _saveMessage(userMessage); // Saving the user message

    final result = await _agent.call(userMessage
        .content); // Sending the message to the agent and getting a response
    final assistantMessage = Message(
        role: 'assistant',
        content:
            result.output); // Creating an assistant message from the response

    setState(() {
      _messages.add(assistantMessage); // Adding assistant message to the list
    });
    await _saveMessage(assistantMessage); // Saving the assistant message
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Murmuration Chatbot'), // Title of the app bar
        actions: [
          DropdownButton<String>(
            value: _selectedLanguage, // Current selected language
            items:
                <String>['en', 'es', 'fr', 'de'] // List of available languages
                    .map<DropdownMenuItem<String>>((String value) {
              return DropdownMenuItem<String>(
                value: value, // Setting the value of the dropdown item
                child: Text(value), // Displaying the language
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                _selectedLanguage = newValue!; // Updating the selected language
                _initializeAgent(); // Reinitialize agent with new language
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
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
}

// Message class to represent a chat message
class Message {
  final String role; // Role of the message sender (user or assistant)
  final String content; // Content of the message

  Message(
      {required this.role, required this.content}); // Constructor for Message

  // Method to convert Message to JSON string
  String toJson() {
    return '{"role": "$role", "content": "$content"}'; // JSON representation of the message
  }

  // Static method to create a Message from a JSON string
  static Message fromJson(String json) {
    final data = jsonDecode(json); // Decoding the JSON string
    return Message(
        role: data['role'],
        content: data['content']); // Creating a Message object
  }
}
