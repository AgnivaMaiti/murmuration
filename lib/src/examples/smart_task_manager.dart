import 'package:flutter/material.dart';
import 'package:murmuration/murmuration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() {
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

  TaskManager(this._murmuration, this._prefs);

  Future<List<Task>> loadTasks() async {
    final tasksJson = _prefs.getStringList(_tasksKey) ?? [];
    return tasksJson.map((json) => Task.fromJson(jsonDecode(json))).toList();
  }

  Future<void> saveTasks(List<Task> tasks) async {
    final tasksJson = tasks.map((task) => jsonEncode(task.toJson())).toList();
    await _prefs.setStringList(_tasksKey, tasksJson);
  }

  Future<Task> createTask(String description) async {
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
}''',
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

    final result = await agent.execute(description);
    final taskData = _parseTaskResponse(result);
    return Task.fromJson(taskData);
  }

  Map<String, dynamic> _parseTaskResponse(AgentResult result) {
    String response = result.output;
    if (result.stream != null) {
      response = result.stream!.join();
    }

    String cleanResponse = response.trim();
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

    final taskData = jsonDecode(cleanResponse) as Map<String, dynamic>;
    if (!taskData.containsKey('id') || taskData['id'] == null) {
      taskData['id'] = 'task-${DateTime.now().millisecondsSinceEpoch}';
    }
    return taskData;
  }

  void dispose() {
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
  String? _error;
  String _selectedProvider = 'google';

  @override
  void initState() {
    super.initState();
    _initializeTaskManager();
  }

  Future<void> _initializeTaskManager() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final config = MurmurationConfig(
        provider: _selectedProvider == 'google'
            ? LLMProvider.google
            : LLMProvider.openai,
        apiKey: 'your-secure-api-key',
        model: _selectedProvider == 'google' ? 'gemini-pro' : 'gpt-3.5-turbo',
        debug: true,
        maxTokens: 1000,
      );

      final murmuration = Murmuration(config);
      _taskManager = TaskManager(murmuration, prefs);
      await _loadTasks();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to initialize: $e');
      }
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
      _error = null;
    });

    try {
      final task = await _taskManager.createTask(_controller.text);
      if (mounted) {
        setState(() => _tasks.add(task));
        await _saveTasks();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _controller.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Task Manager'),
        actions: [
          DropdownButton<String>(
            value: _selectedProvider,
            items: const [
              DropdownMenuItem(value: 'google', child: Text('Google')),
              DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
            ],
            onChanged: (String? newValue) async {
              if (newValue != null) {
                setState(() => _selectedProvider = newValue);
                await _initializeTaskManager();
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
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Describe your task...',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _processTaskInput(),
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                final task = _tasks[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 4.0),
                  child: ListTile(
                    title: Text(task.title),
                    subtitle: Text(task.description),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          task.priority,
                          style: TextStyle(
                            color: task.priority == 'high'
                                ? Colors.red
                                : task.priority == 'medium'
                                    ? Colors.orange
                                    : Colors.green,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${task.dueDate.day}/${task.dueDate.month}/${task.dueDate.year}',
                        ),
                      ],
                    ),
                    leading: Checkbox(
                      value: task.isCompleted,
                      onChanged: (bool? value) async {
                        if (value != null) {
                          setState(() {
                            _tasks[index] = task.copyWith(isCompleted: value);
                          });
                          await _saveTasks();
                        }
                      },
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

  @override
  void dispose() {
    _controller.dispose();
    _taskManager.dispose();
    super.dispose();
  }
}
