import 'dart:async';
import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:murmuration/src/agent/agent_progress.dart';
import 'package:murmuration/src/schema/output_schema.dart';
import '../exceptions.dart';
import '../messaging/message.dart';
import '../tools/tool.dart';
import '../config/murmuration_config.dart';
import '../logging/logger.dart';
import '../messaging/message_history.dart';
import '../state/immutable_state.dart';
import 'agent_result.dart';

class Agent {
  final GenerativeModel _model;
  final ImmutableState _state;
  final List<Tool> _tools;
  final Map<String, FunctionHandler> _functions;
  final MurmurationLogger _logger;
  final MurmurationConfig _config;
  final StreamController<AgentProgress>? _progressController;
  final int _currentAgentIndex;
  final int _totalAgents;
  final ProgressCallback? _onProgress;
  final OutputSchema? _outputSchema;
  MessageHistory? _messageHistory;

  Agent._({
    required GenerativeModel model,
    required ImmutableState state,
    required List<Tool> tools,
    required Map<String, FunctionHandler> functions,
    required MurmurationLogger logger,
    required MurmurationConfig config,
    StreamController<AgentProgress>? progressController,
    required int currentAgentIndex,
    required int totalAgents,
    ProgressCallback? onProgress,
    OutputSchema? outputSchema,
    MessageHistory? messageHistory,
  })  : _model = model,
        _state = state,
        _tools = tools,
        _functions = functions,
        _logger = logger,
        _config = config,
        _progressController = progressController,
        _currentAgentIndex = currentAgentIndex,
        _totalAgents = totalAgents,
        _onProgress = onProgress,
        _outputSchema = outputSchema,
        _messageHistory = messageHistory;

  static AgentBuilder builder(GenerativeModel model) => AgentBuilder(model);

  void addTool(Tool tool) {
    (_tools).add(tool);
    _logger.log('Added tool: ${tool.name}');
  }

  void addFunction(String name, FunctionHandler handler) {
    (_functions)[name] = handler;
    _logger.log('Added function: $name');
  }

  Future<void> handoff(Agent nextAgent) async {
    nextAgent.updateState(_state.toMap());
    _logger.log('State handed off to next agent');
  }

  void updateState(Map<String, dynamic> newState) {
    (_state).copyWith(newState);
    _logger.log('State updated: ${_state.toMap()}');
  }

  Future<void> initializeHistory(String threadId) async {
    _messageHistory = MessageHistory(threadId: threadId);
    await _messageHistory!.load();
    _logger.log('Initialized message history for thread: $threadId');
  }

  Future<AgentResult> call(String input) => execute(input);

  Future<void> dispose() async {
    await _progressController?.close();
    _logger.log('Agent disposed');
  }

  Map<String, dynamic> getState() => _state.toMap();

  List<Tool> getTools() => List.unmodifiable(_tools);

  Map<String, FunctionHandler> getFunctions() => Map.unmodifiable(_functions);

  bool get hasSchema => _outputSchema != null;

  bool get hasMessageHistory => _messageHistory != null;

  @override
  String toString() {
    return 'Agent(currentIndex: $_currentAgentIndex, '
        'totalAgents: $_totalAgents, '
        'toolCount: ${_tools.length}, '
        'functionCount: ${_functions.length})';
  }
}

typedef FunctionHandler = Future<dynamic> Function(
    Map<String, dynamic> parameters);

typedef ProgressCallback = void Function(AgentProgress progress);

class AgentBuilder {
  final GenerativeModel _model;
  ImmutableState _state = ImmutableState();
  final List<Tool> _tools = [];
  final Map<String, FunctionHandler> _functions = {};
  MurmurationLogger? _logger;
  MurmurationConfig? _config;
  StreamController<AgentProgress>? _progressController;
  int _currentAgentIndex = 1;
  int _totalAgents = 1;
  ProgressCallback? _onProgress;
  OutputSchema? _outputSchema;
  MessageHistory? _messageHistory;

  AgentBuilder(this._model);

  AgentBuilder withState(Map<String, dynamic> state) {
    _state = _state.copyWith(state);
    return this;
  }

  AgentBuilder addTool(Tool tool) {
    _tools.add(tool);
    return this;
  }

  AgentBuilder addFunction(String name, FunctionHandler handler) {
    _functions[name] = handler;
    return this;
  }

  AgentBuilder withConfig(MurmurationConfig config) {
    _config = config;
    return this;
  }

  AgentBuilder withProgress({
    required int current,
    required int total,
    ProgressCallback? callback,
  }) {
    _currentAgentIndex = current;
    _totalAgents = total;
    _onProgress = callback;
    return this;
  }

  AgentBuilder withSchema(OutputSchema schema) {
    _outputSchema = schema;
    return this;
  }

  AgentBuilder withMessageHistory(String threadId) {
    _messageHistory = MessageHistory(threadId: threadId);
    return this;
  }

  Future<Agent> build() async {
    final config = _config ?? const MurmurationConfig(apiKey: '');
    final logger = _logger ?? config.logger;

    if (_messageHistory != null) {
      await _messageHistory!.load();
    }

    return Agent._(
      model: _model,
      state: _state,
      tools: List.unmodifiable(_tools),
      functions: Map.unmodifiable(_functions),
      logger: logger,
      config: config,
      progressController: _progressController,
      currentAgentIndex: _currentAgentIndex,
      totalAgents: _totalAgents,
      onProgress: _onProgress,
      outputSchema: _outputSchema,
      messageHistory: _messageHistory,
    );
  }
}

extension AgentExecution on Agent {
  Future<AgentResult> execute(String input) async {
    try {
      _reportProgress('Starting execution', output: input);

      if (_messageHistory != null) {
        await _messageHistory!.addMessage(Message(
          role: 'user',
          content: input,
        ));
      }

      final prompt = _buildPrompt(input);

      if (_config.stream) {
        return AgentResult(
          output: '',
          stateVariables: _state.toMap(),
          stream: _streamResponse(prompt),
        );
      }

      return await _executeWithRetry(prompt);
    } catch (e, stackTrace) {
      _logger.error('Execution error', e, stackTrace);
      rethrow;
    }
  }

  Future<AgentResult> _executeWithRetry(String prompt) async {
    int attempts = 0;
    while (attempts < _config.maxRetries) {
      try {
        return await _executePrompt(prompt);
      } catch (e) {
        attempts++;
        if (attempts >= _config.maxRetries) rethrow;

        _logger.error(
          'Execution attempt $attempts failed, retrying...',
          e,
        );
        await Future.delayed(_config.retryDelay);
      }
    }
    throw MurmurationException('Maximum retry attempts exceeded');
  }

  Future<AgentResult> _executePrompt(String prompt) async {
    final content = [Content.text(prompt)];
    final response = await _model.generateContent(content).timeout(
      _config.timeout,
      onTimeout: () {
        throw MurmurationException('Request timed out');
      },
    );

    _reportProgress('Received response', output: response.text);

    final responseText = response.text ?? '';

    if (_messageHistory != null && responseText.isNotEmpty) {
      await _messageHistory!.addMessage(Message(
        role: 'assistant',
        content: responseText,
      ));
    }

    if (responseText.contains('function:')) {
      return await _handleFunctionCall(responseText);
    }

    if (_outputSchema != null) {
      return await _handleSchemaValidation(responseText);
    }

    return AgentResult(
      output: responseText,
      stateVariables: _state.toMap(),
    );
  }

  Future<AgentResult> _handleFunctionCall(String text) async {
    final functionCall = _parseFunctionCall(text);
    final result = await _executeFunctionCall(
      functionCall.name,
      functionCall.parameters,
    );

    if (result is AgentResult) return result;

    return AgentResult(
      output: result.toString(),
      stateVariables: _state.toMap(),
    );
  }

  Future<dynamic> _executeFunctionCall(
      String name, Map<String, dynamic> parameters) async {
    final handler = _functions[name];
    if (handler == null) {
      throw MurmurationException('Function not found: $name');
    }

    try {
      _logger.log('Executing function: $name with parameters: $parameters');
      final result = await handler(parameters);
      _logger.log('Function execution completed');
      return result;
    } catch (e, stackTrace) {
      throw MurmurationException(
        'Function execution failed',
        e,
        stackTrace,
      );
    }
  }

  Future<AgentResult> _handleSchemaValidation(String text) async {
    try {
      final parsedOutput = _parseOutput(text);
      final validatedOutput = _outputSchema!.validateAndConvert(parsedOutput);

      if (!validatedOutput.isValid) {
        throw MurmurationException(
          'Schema validation failed: ${validatedOutput.errors.join(", ")}',
        );
      }

      return AgentResult(
        output: jsonEncode(validatedOutput.data),
        stateVariables: _state.toMap(),
      );
    } catch (e, stackTrace) {
      throw MurmurationException(
        'Output validation failed',
        e,
        stackTrace,
      );
    }
  }

  Map<String, dynamic> _parseOutput(String text) {
    try {
      try {
        return jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        final Map<String, dynamic> result = {};
        final lines = text.split('\n');

        for (final line in lines) {
          final parts = line.split(':');
          if (parts.length >= 2) {
            final key = parts[0].trim();
            final value = parts.sublist(1).join(':').trim();
            result[key] = value;
          }
        }

        return result;
      }
    } catch (e, stackTrace) {
      throw MurmurationException(
        'Failed to parse output',
        e,
        stackTrace,
      );
    }
  }

  Stream<String> _streamResponse(String prompt) async* {
    _reportProgress('Starting stream response');

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);

      if (response.text != null) {
        final chunks = response.text!.split(' ');
        for (var chunk in chunks) {
          _reportProgress('Streaming chunk', output: chunk);
          yield '$chunk ';
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    } catch (e, stackTrace) {
      _logger.error('Streaming error', e, stackTrace);
      rethrow;
    }
  }

  void _reportProgress(String status, {String? output}) {
    final progress = AgentProgress(
      currentAgent: _currentAgentIndex,
      totalAgents: _totalAgents,
      status: status,
      output: output,
    );

    _progressController?.add(progress);
    _onProgress?.call(progress);
    _logger.log(progress.toString());
  }

  FunctionCall _parseFunctionCall(String text) {
    final regex = RegExp(r'function:\s*(\w+)\s*\((.*)\)');
    final match = regex.firstMatch(text);

    if (match == null) {
      throw MurmurationException('Invalid function call format');
    }

    try {
      return FunctionCall(
        name: match.group(1)!,
        parameters: _parseFunctionParameters(match.group(2)!),
      );
    } catch (e, stackTrace) {
      throw MurmurationException(
        'Failed to parse function call',
        e,
        stackTrace,
      );
    }
  }

  Map<String, dynamic> _parseFunctionParameters(String paramsStr) {
    try {
      return Map.fromEntries(
        paramsStr.split(',').map((p) => p.trim().split(':')).map(
            (p) => MapEntry(p[0].trim(), _parseParameterValue(p[1].trim()))),
      );
    } catch (e, stackTrace) {
      throw MurmurationException(
        'Failed to parse function parameters',
        e,
        stackTrace,
      );
    }
  }

  dynamic _parseParameterValue(String value) {
    if (value.toLowerCase() == 'true') return true;
    if (value.toLowerCase() == 'false') return false;
    if (value == 'null') return null;

    final number = num.tryParse(value);
    if (number != null) {
      if (number == number.toInt()) {
        return number.toInt();
      }
      return number;
    }

    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      return value.substring(1, value.length - 1);
    }

    return value;
  }

  String _buildPrompt(String input) {
    final toolsDescription = _tools.isEmpty
        ? ''
        : '''
Available tools:
${_tools.map((t) => '- ${t.name}: ${t.description}').join('\n')}
''';

    final functionsDescription = _functions.isEmpty
        ? ''
        : '''
Available functions:
${_functions.keys.map((name) => '- $name').join('\n')}
''';

    return '''
Instructions: ${_state.get<String>('role') ?? 'Assistant'}
$toolsDescription
$functionsDescription
Context: ${_state.toMap().toString()}
Input: $input
''';
  }
}
