import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:murmuration/murmuration.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(
      const MyApp()); // Entry point of the application, runs the MyApp widget
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
  Murmuration? _murmuration;
  String _selectedProvider = 'anthropic';
  bool _isLoading = false;
  String? _error;
  final List<Message> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Available LLM providers
  final Map<String, String> _providers = {
    'anthropic': 'Anthropic (Claude)',
    'openai': 'OpenAI (GPT)',
    'google': 'Google (Gemini)',
  };

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

  // Initialize Murmuration with the selected provider
  Future<void> _initializeMurmuration() async {
    try {
      setState(() => _isLoading = true);

      final apiKey = _getApiKeyForProvider(_selectedProvider);
      if (apiKey == null) {
        throw Exception('API key not found for $_selectedProvider');
      }

      final config = MurmurationConfig(
        provider: _getProviderFromString(_selectedProvider),
        apiKey: apiKey,
        modelConfig: ModelConfig(
          modelName: _getModelForProvider(_selectedProvider),
          temperature: 0.7,
          maxTokens: 1000,
        ),
        cacheConfig: CacheConfig(
          enabled: true,
          ttl: const Duration(hours: 1),
        ),
      );

      _murmuration = Murmuration(config);
      await _loadMessages();

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to initialize: $e';
          _isLoading = false;
        });
      }
    }
  }

  String? _getApiKeyForProvider(String provider) {
    switch (provider) {
      case 'anthropic':
        return dotenv.env['ANTHROPIC_API_KEY'];
      case 'openai':
        return dotenv.env['OPENAI_API_KEY'];
      case 'google':
        return dotenv.env['GEMINI_API_KEY'];
      default:
        return null;
    }
  }

  LLMProvider _getProviderFromString(String provider) {
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

  String _getModelForProvider(String provider) {
    switch (provider) {
      case 'anthropic':
        return 'claude-3-sonnet-20240229';
      case 'openai':
        return 'gpt-4-turbo';
      case 'google':
        return 'gemini-pro';
      default:
        return 'claude-3-sonnet-20240229';
    }
  }

  // Load chat history from shared preferences
  Future<void> _loadMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMessages = prefs.getStringList('chat_history') ?? [];

      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(savedMessages.map((msg) => Message.fromJson(msg)));
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to load messages: $e');
      }
    }
  }

  // Save messages to shared preferences
  Future<void> _saveMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'chat_history',
        _messages.map((msg) => msg.toJson()).toList(),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to save messages: $e');
      }
    }
  }

  // Handle sending a message
  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _murmuration == null) return;

    final message = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(message);
      _textController.clear();
    });

    _scrollToBottom();
    await _saveMessages();

    try {
      final agent = await _murmuration!.createAgent({
        'role': 'Assistant',
        'language': _selectedLanguage,
      });

      final result = await agent.execute(text);

      if (result.stream != null) {
        String assistantResponse = '';
        await for (final chunk in result.stream!) {
          assistantResponse += chunk;
          if (mounted) {
            setState(() {
              if (_messages.last.isUser) {
                _messages.last =
                    Message.fromJson(jsonEncode({
                  'id': _messages.last.id,
                  'text': assistantResponse,
                  'isUser': false,
                  'timestamp': _messages.last.timestamp,
                }));
              } else {
                _messages.add(
                    Message.fromJson(jsonEncode({
                  'id': DateTime.now().millisecondsSinceEpoch.toString(),
                  'text': assistantResponse,
                  'isUser': false,
                  'timestamp': DateTime.now(),
                })));
              }
            });
          }
        }
        await _saveMessages();
      } else {
        final assistantMessage = Message.fromJson(jsonEncode({
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'text': result.output.trim(),
          'isUser': false,
          'timestamp': DateTime.now(),
        }));

        if (mounted) {
          setState(() => _messages.add(assistantMessage));
        }
        await _saveMessages();
      }
    } catch (e) {
      setState(() {
        _error = 'Error generating response: $e';
        _messages.removeLast(); // Remove the bot's message if there was an error
      });
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _changeProvider(String? provider) {
    if (provider == null || provider == _selectedProvider) return;

    setState(() => _selectedProvider = provider);
    _initializeMurmuration();
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
        title: const Text('Murmuration Chatbot'),
        actions: [
          // Provider selection dropdown
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: DropdownButton<String>(
              value: _selectedProvider,
              items: _providers.entries.map((entry) {
                return DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value),
                );
              }).toList(),
              onChanged: _changeProvider,
              underline: const SizedBox(),
              dropdownColor: Theme.of(context).cardColor,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Error banner
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(8.0),
              color: Colors.red[100],
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8.0),
                  Expanded(child: Text(_error!)),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => setState(() => _error = null),
                  ),
                ],
              ),
            ),

          // Chat messages
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8.0),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return _buildMessageBubble(message);
                    },
                  ),
          ),

          // Input area
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4.0,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Message input
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16.0),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),

                // Send button
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                  tooltip: 'Send message',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message) {
    final isUser = message.isUser;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const CircleAvatar(
              child: Icon(Icons.smart_toy, size: 16.0),
            ),
            const SizedBox(width: 8.0),
          ],

          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                vertical: 10.0,
                horizontal: 14.0,
              ),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(20.0),
                boxShadow: [
                  if (!isUser)
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 2.0,
                      offset: const Offset(0, 1),
                    ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    message.text,
                    style: TextStyle(
                      color: isUser
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),

                  if (message.metadata != null && !isUser) ...[
                    const SizedBox(height: 4.0),
                    Text(
                      'Model: ${message.metadata!['model'] ?? 'N/A'} • '
                      'Tokens: ${message.metadata!['tokens'] ?? 'N/A'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: (isUser
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurfaceVariant)
                            ?.withOpacity(0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          if (isUser) ...[
            const SizedBox(width: 8.0),
            CircleAvatar(
              child: Text(
                'U',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                ),
              ),
              backgroundColor: theme.colorScheme.primary,
              radius: 12.0,
            ),
          ],
        ],
      ),
    );
  }
}

// Message class to represent a chat message
class Message {
  final String id;
  String text;
  final bool isUser;
  final DateTime timestamp;
  Map<String, dynamic>? metadata;

  Message({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.metadata,
  });

  String toJson() => jsonEncode({
        'id': id,
        'text': text,
        'isUser': isUser,
        'timestamp': timestamp.toIso8601String(),
        'metadata': metadata,
      });

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'isUser': isUser,
        'timestamp': timestamp.toIso8601String(),
        'metadata': metadata,
      };

  factory Message.fromJson(String json) {
    final data = jsonDecode(json);
    return Message(
      id: data['id'] ?? '',
      text: data['text'] ?? '',
      isUser: data['isUser'] ?? false,
      timestamp: DateTime.parse(data['timestamp'] ?? DateTime.now().toIso8601String()),
      metadata: data['metadata'] is Map ? Map<String, dynamic>.from(data['metadata']) : null,
    );
  }
}
