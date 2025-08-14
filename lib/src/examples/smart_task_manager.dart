import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:murmuration/murmuration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const SmartTaskManagerApp());
}

class SmartTaskManagerApp extends StatelessWidget {
  const SmartTaskManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Task Manager',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const TaskManagerScreen(),
    );
  }
}

class Task {
  final String id;
  final String title;
  final String description;
  final DateTime dueDate;
  final String priority;
  final bool isCompleted;

  const Task({
    required this.id,
    required this.title,
    required this.description,
    required this.dueDate,
    required this.priority,
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'dueDate': dueDate.toIso8601String(),
        'priority': priority,
        'isCompleted': isCompleted,
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'],
        title: json['title'],
        description: json['description'],
        dueDate: DateTime.parse(json['dueDate']),
        priority: json['priority'],
        isCompleted: json['isCompleted'],
      );

  Task copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? dueDate,
    String? priority,
    bool? isCompleted,
  }) =>
      Task(
        id: id ?? this.id,
        title: title ?? this.title,
        description: description ?? this.description,
        dueDate: dueDate ?? this.dueDate,
        priority: priority ?? this.priority,
        isCompleted: isCompleted ?? this.isCompleted,
      );
}

class TaskManager {
  final Murmuration _murmuration;
  final SharedPreferences _prefs;
  static const String _tasksKey = 'tasks';
  StreamController<String>? _streamController;
  bool _isDisposed = false;

  TaskManager(this._murmuration, this._prefs);

  Stream<String> get stream => _streamController?.stream ?? const Stream.empty();

  bool get isDisposed => _isDisposed;

  Future<List<Task>> loadTasks() async {
    final tasksJson = _prefs.getStringList(_tasksKey) ?? [];
    return tasksJson.map((json) => Task.fromJson(jsonDecode(json))).toList();
  }

  Future<void> saveTasks(List<Task> tasks) async {
    final tasksJson = tasks.map((task) => jsonEncode(task.toJson())).toList();
    await _prefs.setStringList(_tasksKey, tasksJson);
  }

  Future<Task> createTask(String description, {Function(String)? onStream}) async {
    _streamController = StreamController<String>();
    StringBuffer fullResponse = StringBuffer();
    
    final agent = await _murmuration.createAgent({
      'role':
          '''You are an AI Task Management Assistant that creates tasks from user descriptions.

IMPORTANT: You must ALWAYS respond with ONLY a valid JSON object in this exact format:
{
  "id": "task-[timestamp]",
  "title": "Brief task title",
  "description": "Detailed task description",
  "dueDate": "2025-03-14T10:00:00Z",
  "priority": "high/medium/low",
  "isCompleted": false
}

For dates:
- If user specifies a date/time, use it
- If user says "today", use current date
- If user says "tomorrow", add 1 day to current date
- If user says "next week", add 7 days to current date
- Default to 3 days from now if no date specified

For priority:
- high: due within 24 hours
- medium: due within 3 days
- low: due after 3 days

Example input: "Schedule team meeting next week"
You must respond with ONLY this (no other text):
{
  "id": "task-1234",
  "title": "Team Meeting",
  "description": "Schedule and organize team meeting for next week",
  "dueDate": "2025-03-27T10:00:00Z",
  "priority": "medium",
  "isCompleted": false
}

IMPORTANT: Stream the response as it's being generated.''',
      'stream': true,
    });

    agent.addFunction('get_current_time', (params) async {
      return DateTime.now().toIso8601String();
    });

    agent.addFunction('parse_date', (params) async {
      final dateStr = params['date'] as String;
      try {
        return DateTime.parse(dateStr).toIso8601String();
      } catch (e) {
        throw Exception('Invalid date format');
      }
    });

    agent.addFunction('suggest_priority', (params) async {
      final description = params['description'] as String;
      final dueDate = DateTime.parse(params['dueDate'] as String);
      final now = DateTime.now();

      if (dueDate.isBefore(now)) return 'high';
      if (dueDate.difference(now).inDays <= 1) return 'high';
      if (dueDate.difference(now).inDays <= 3) return 'medium';
      return 'low';
    });

    try {
      final result = await agent.execute(description);
      
      // Handle streaming response
      if (result.stream != null) {
        await for (final chunk in result.stream!) {
          if (_isDisposed) break;
          fullResponse.write(chunk);
          _streamController?.add(chunk);
          onStream?.call(chunk);
        }
        await _streamController?.close();
      } else {
        fullResponse.write(result.output);
        _streamController?.add(result.output);
        await _streamController?.close();
      }

      final taskData = _parseTaskResponse(fullResponse.toString());
      return Task.fromJson(taskData);
    } catch (e) {
      _streamController?.addError('Error creating task: $e');
      await _streamController?.close();
      rethrow;
    }
  }

  Map<String, dynamic> _parseTaskResponse(String response) {
    try {
      String cleanResponse = response.trim();
      
      // Handle code block formatting
      if (cleanResponse.startsWith('```json')) {
        cleanResponse = cleanResponse.substring(7);
      }
      if (cleanResponse.startsWith('```')) {
        cleanResponse = cleanResponse.substring(3);
      }
      if (cleanResponse.endsWith('```')) {
        cleanResponse = cleanResponse.substring(0, cleanResponse.length - 3);
      }
      cleanResponse = cleanResponse.trim();

      // Try to parse as JSON
      final taskData = jsonDecode(cleanResponse) as Map<String, dynamic>;
      
      // Ensure required fields exist
      if (!taskData.containsKey('id') || taskData['id'] == null) {
        taskData['id'] = 'task-${DateTime.now().millisecondsSinceEpoch}';
      }
      if (!taskData.containsKey('title') || taskData['title'] == null) {
        taskData['title'] = 'New Task';
      }
      if (!taskData.containsKey('description') || taskData['description'] == null) {
        taskData['description'] = '';
      }
      if (!taskData.containsKey('dueDate') || taskData['dueDate'] == null) {
        taskData['dueDate'] = DateTime.now().add(const Duration(days: 3)).toIso8601String();
      }
      if (!taskData.containsKey('priority') || taskData['priority'] == null) {
        taskData['priority'] = 'medium';
      }
      
      return taskData;
    } catch (e) {
      throw FormatException('Failed to parse task response: $e\nResponse: $response');
    }
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await _streamController?.close();
    _murmuration.dispose();
  }
}

class TaskManagerScreen extends StatefulWidget {
  const TaskManagerScreen({super.key});

  @override
  _TaskManagerScreenState createState() => _TaskManagerScreenState();
}

class _TaskManagerScreenState extends State<TaskManagerScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Task> _tasks = [];
  late TaskManager _taskManager;
  bool _isLoading = false;
  bool _isStreaming = false;
  String? _error;
  String _selectedProvider = 'anthropic';
  String _streamedText = '';
  final ScrollController _scrollController = ScrollController();
  
  // Available providers with their display names and models
  final Map<String, Map<String, String>> _providers = {
    'anthropic': {'name': 'Anthropic', 'model': 'claude-3-opus-20240229'},
    'openai': {'name': 'OpenAI', 'model': 'gpt-3.5-turbo'},
    'google': {'name': 'Google', 'model': 'gemini-pro'},
  };

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _initializeTaskManager();
  }

  Future<void> _initializeTaskManager() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final prefs = await SharedPreferences.getInstance();
      final provider = _getProviderFromString(_selectedProvider);
      final model = _providers[_selectedProvider]?['model'] ?? 'claude-3-opus-20240229';
      
      // Get API key from environment variables
      final apiKey = _getApiKeyForProvider(_selectedProvider);
      if (apiKey == null) {
        throw Exception('API key not found for ${_providers[_selectedProvider]?['name']}');
      }

      final config = MurmurationConfig(
        provider: provider,
        apiKey: apiKey,
        modelConfig: ModelConfig(
          modelName: model,
          maxTokens: 2000,
          temperature: 0.7,
        ),
        debug: true,
      );

      final murmuration = Murmuration(config);
      _taskManager = TaskManager(murmuration, prefs);
      
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to initialize ${_providers[_selectedProvider]?['name']}: $e';
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

  Future<void> _loadTasks() async {
    try {
      final tasks = await _taskManager.loadTasks();
      if (mounted) {
        setState(() => _tasks.addAll(tasks));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to load tasks: $e');
      }
    }
  }

  Future<void> _saveTasks() async {
    try {
      await _taskManager.saveTasks(_tasks);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to save tasks: $e');
      }
    }
  }

  Future<void> _processTaskInput() async {
    if (_controller.text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _isStreaming = true;
      _streamedText = '';
      _error = null;
    });

    try {
      final task = await _taskManager.createTask(
        _controller.text,
        onStream: (chunk) {
          if (!mounted || _taskManager.isDisposed) return;
          
          setState(() {
            _streamedText += chunk;
            // Auto-scroll to bottom when new content is added
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            });
          });
        },
      );
      
      if (mounted) {
        setState(() {
          _tasks.insert(0, task); // Add new task at the beginning of the list
          _streamedText = '';
        });
        await _saveTasks();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Error creating task: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isStreaming = false;
        });
        _controller.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Task Manager'),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: DropdownButton<String>(
              value: _selectedProvider,
              underline: const SizedBox(),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
              items: _providers.entries.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value['name'] ?? entry.key),
                );
              }).toList(),
              onChanged: (String? newValue) async {
                if (newValue != null && newValue != _selectedProvider) {
                  setState(() => _selectedProvider = newValue);
                  await _initializeTaskManager();
                }
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Error banner
          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.red[50],
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => setState(() => _error = null),
                  ),
                ],
              ),
            ),
          
          // Task input area
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: theme.cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Provider info
                Row(
                  children: [
                    const Icon(Icons.psychology, size: 16, color: Colors.blueGrey),
                    const SizedBox(width: 8),
                    Text(
                      'Using: ${_providers[_selectedProvider]?['name']} (${_providers[_selectedProvider]?['model']})',
                      style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.blueGrey,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Input field
                TextField(
                  controller: _controller,
                  maxLines: 2,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: 'Describe your task (e.g., "Schedule team meeting next week")',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    suffixIcon: _isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.send, color: Colors.blue),
                            onPressed: _processTaskInput,
                          ),
                  ),
                  onSubmitted: (_) => _processTaskInput(),
                  enabled: !_isLoading,
                ),
              ],
            ),
          ),
          
          // Streaming output
          if (_isStreaming && _streamedText.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.blue[100]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Generating task...',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _streamedText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          // Tasks list header
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Your Tasks (${_tasks.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (_tasks.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      // Show confirmation dialog before clearing all tasks
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Clear All Tasks'),
                          content: const Text(
                              'Are you sure you want to delete all tasks? This action cannot be undone.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('CANCEL'),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() => _tasks.clear());
                                _saveTasks();
                                Navigator.pop(context);
                              },
                              child: const Text('DELETE',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Clear All'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
              ],
            ),
          ),
          
          // Tasks list
          Expanded(
            child: _tasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.task_alt,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No tasks yet',
                          style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.grey,
                              ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Describe a task above to get started',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _tasks.length,
                    padding: const EdgeInsets.only(bottom: 16.0),
                    itemBuilder: (context, index) {
                      final task = _tasks[index];
                      final isOverdue = !task.isCompleted &&
                          task.dueDate.isBefore(DateTime.now());
                      
                      return Dismissible(
                        key: Key(task.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20.0),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (direction) async {
                          // Show confirmation dialog
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete Task'),
                              content: const Text(
                                  'Are you sure you want to delete this task?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('CANCEL'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: const Text('DELETE',
                                      style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                          return confirmed ?? false;
                        },
                        onDismissed: (direction) {
                          setState(() => _tasks.removeAt(index));
                          _saveTasks();
                        },
                        child: Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 4.0,
                          ),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            side: isOverdue
                                ? const BorderSide(color: Colors.red, width: 1)
                                : BorderSide.none,
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 4.0,
                            ),
                            leading: Checkbox(
                              value: task.isCompleted,
                              onChanged: (bool? value) async {
                                if (value != null) {
                                  setState(() {
                                    _tasks[index] =
                                        task.copyWith(isCompleted: value);
                                  });
                                  await _saveTasks();
                                }
                              },
                            ),
                            title: Text(
                              task.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                decoration: task.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: task.isCompleted
                                    ? Colors.grey
                                    : null,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (task.description.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    task.description,
                                    style: TextStyle(
                                      color: task.isCompleted
                                          ? Colors.grey[500]
                                          : Colors.grey[700],
                                      fontSize: 14,
                                      decoration: task.isCompleted
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    _buildPriorityChip(task.priority),
                                    const SizedBox(width: 8),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.calendar_today,
                                          size: 14,
                                          color: isOverdue
                                              ? Colors.red
                                              : Colors.grey[600],
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatDate(task.dueDate),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isOverdue
                                                ? Colors.red
                                                : Colors.grey[600],
                                            fontWeight: isOverdue
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (isOverdue) ...[
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Overdue!',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // Helper method to build priority chip
  Widget _buildPriorityChip(String priority) {
    Color backgroundColor;
    Color textColor;
    
    switch (priority.toLowerCase()) {
      case 'high':
        backgroundColor = Colors.red[50]!;
        textColor = Colors.red[800]!;
        break;
      case 'medium':
        backgroundColor = Colors.orange[50]!;
        textColor = Colors.orange[800]!;
        break;
      case 'low':
      default:
        backgroundColor = Colors.green[50]!;
        textColor = Colors.green[800]!;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
  
  // Helper method to format date
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = date.difference(DateTime(now.year, now.month, now.day));
    
    if (difference.inDays == 0) {
      return 'Today, ${_formatTime(date)}';
    } else if (difference.inDays == 1) {
      return 'Tomorrow, ${_formatTime(date)}';
    } else if (difference.inDays == -1) {
      return 'Yesterday, ${_formatTime(date)}';
    } else if (difference.inDays < 7 && difference.inDays > -7) {
      return '${_getWeekday(date.weekday)}, ${_formatTime(date)}';
    }
    
    return '${date.day}/${date.month}/${date.year}, ${_formatTime(date)}';
  }
  
  String _formatTime(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final period = date.hour < 12 ? 'AM' : 'PM';
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }
  
  String _getWeekday(int weekday) {
    switch (weekday) {
      case 1: return 'Monday';
      case 2: return 'Tuesday';
      case 3: return 'Wednesday';
      case 4: return 'Thursday';
      case 5: return 'Friday';
      case 6: return 'Saturday';
      case 7: return 'Sunday';
      default: return '';
    }
  }
  
  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _taskManager.dispose();
    super.dispose();
  }
}
