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
import '../client/openai_client.dart';

typedef FunctionHandler = Future<String> Function(Map<String, dynamic>);

class FunctionCall {
  final String name;
  final Map<String, dynamic> arguments;

  FunctionCall({
    required this.name,
    required this.arguments,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'arguments': arguments,
      };
}

class Agent {
  final dynamic _model;
  final MurmurationConfig _config;
  final ImmutableState _state;
  final MurmurationLogger _logger;
  final MessageHistory _history;
  final List<Tool> _tools;
  final Map<String, FunctionHandler> _functions;
  final OutputSchema? _outputSchema;
  final int _currentIndex;
  final int _totalAgents;
  final ProgressCallback? _onProgress;
  bool _isDisposed = false;

  Agent._internal({
    required dynamic model,
    required MurmurationConfig config,
    required ImmutableState state,
    required MessageHistory history,
    required List<Tool> tools,
    required Map<String, FunctionHandler> functions,
    required OutputSchema? outputSchema,
    required int currentIndex,
    required int totalAgents,
    required ProgressCallback? onProgress,
  })  : _model = model,
        _config = config,
        _state = state,
        _logger = config.logger,
        _history = history,
        _tools = tools,
        _functions = functions,
        _outputSchema = outputSchema,
        _currentIndex = currentIndex,
        _totalAgents = totalAgents,
        _onProgress = onProgress;

  static _AgentBuilder builder(dynamic model) {
    return _AgentBuilder(model);
  }

  void addTool(Tool tool) {
    if (_isDisposed) {
      throw StateException(
        'Agent has been disposed',
        errorDetails: {'agentIndex': _currentIndex, 'totalAgents': _totalAgents},
      );
    }
    _tools.add(tool);
    _logger.info('Added tool: ${tool.name}');
  }

  void addFunction(String name, FunctionHandler handler) {
    if (_isDisposed) {
      throw StateException(
        'Agent has been disposed',
        errorDetails: {'agentIndex': _currentIndex, 'totalAgents': _totalAgents},
      );
    }
    _functions[name] = handler;
    _logger.info('Added function: $name');
  }

  @override
  Future<AgentResult> execute(String input) async {
    if (_isDisposed) {
      throw StateException(
        'Agent has been disposed',
        errorDetails: {'agentIndex': _currentIndex, 'totalAgents': _totalAgents},
      );
    }

    try {
      _updateProgress(AgentStatus.initializing);
      await _validateInput(input);

      _updateProgress(AgentStatus.processing);
      final messages = await _prepareMessages(input);
      final response = await _getModelResponse(messages);

      _updateProgress(AgentStatus.postProcessing);
      final result = await _processResponse(response);

      _updateProgress(AgentStatus.completed);
      return result;
    } catch (e, stackTrace) {
      _updateProgress(AgentStatus.error);
      _handleError(e, stackTrace);
      throw MurmurationException(
        'Failed to execute agent',
        code: ErrorCode.unknownError,
        errorDetails: {
          'agentIndex': _currentIndex,
          'totalAgents': _totalAgents,
          'state': _state.toMap(),
        },
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _validateInput(String input) async {
    if (input.isEmpty) {
      throw ValidationException(
        'Input cannot be empty',
        code: ErrorCode.invalidInput,
      );
    }
    _logger.debug('Validated input');
  }

  Future<List<Message>> _prepareMessages(String input) async {
    final messages = <Message>[];
    messages.add(Message(
      role: MessageRole.system,
      content: _getSystemPrompt(),
    ));
    messages.add(Message(
      role: MessageRole.user,
      content: input,
    ));
    _logger.debug('Prepared messages');
    return messages;
  }

  Future<Map<String, dynamic>> _getModelResponse(List<Message> messages) async {
    try {
      final response = await _model.chatCompletion(
        messages: messages,
        stream: _config.stream,
        functions: _getFunctionDefinitions(),
      );
      _logger.debug('Got model response');
      return response;
    } catch (e, stackTrace) {
      _logger.error('Failed to get model response', e, stackTrace);
      throw MurmurationException(
        'Failed to get model response',
        code: ErrorCode.modelError,
        errorDetails: {
          'model': _config.modelConfig.modelName,
          'provider': _config.provider.name,
        },
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<AgentResult> _processResponse(Map<String, dynamic> response) async {
    try {
      final functionCall = _extractFunctionCall(response);
      if (functionCall != null) {
        return await _handleFunctionCall(functionCall);
      }
      return AgentResult(
        output: response['choices'][0]['message']['content'],
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to process response', e, stackTrace);
      throw MurmurationException(
        'Failed to process response',
        code: ErrorCode.invalidOutput,
        errorDetails: {'response': response},
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  FunctionCall? _extractFunctionCall(Map<String, dynamic> response) {
    final message = response['choices'][0]['message'];
    final functionCall = message['function_call'];
    if (functionCall != null) {
      return FunctionCall(
        name: functionCall['name'],
        arguments: functionCall['arguments'],
      );
    }
    return null;
  }

  Future<AgentResult> _handleFunctionCall(FunctionCall functionCall) async {
    final handler = _functions[functionCall.name];
    if (handler == null) {
      throw MurmurationException(
        'Unknown function: ${functionCall.name}',
        code: ErrorCode.invalidFunction,
        errorDetails: {
          'function': functionCall.name,
          'availableFunctions': _functions.keys.toList(),
        },
      );
    }

    try {
      final result = await handler(functionCall.arguments);
      return AgentResult(
        output: result,
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to handle function call', e, stackTrace);
      throw MurmurationException(
        'Failed to handle function call',
        code: ErrorCode.functionError,
        errorDetails: {
          'function': functionCall.name,
          'arguments': functionCall.arguments,
        },
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  List<Map<String, dynamic>> _getFunctionDefinitions() {
    return _functions.entries.map((entry) {
      return {
        'name': entry.key,
        'description': 'Execute function ${entry.key}',
        'parameters': {
          'type': 'object',
          'properties': {},
          'required': [],
        },
      };
    }).toList();
  }

  void _handleError(dynamic error, StackTrace? stackTrace) {
    _logger.error('Agent error', error, stackTrace);
    if (_onProgress != null) {
      _onProgress!(
        AgentProgress(
          status: AgentStatus.error,
          currentAgent: _currentIndex,
          totalAgents: _totalAgents,
          timestamp: DateTime.now(),
          metadata: {'error': error.toString()},
        ),
      );
    }
  }

  void _updateProgress(AgentStatus status) {
    if (_onProgress != null) {
      _onProgress!(
        AgentProgress(
          status: status,
          currentAgent: _currentIndex,
          totalAgents: _totalAgents,
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  String _getSystemPrompt() {
    final buffer = StringBuffer();
    buffer.writeln('You are an AI agent with the following tools:');
    for (final tool in _tools) {
      buffer.writeln('- ${tool.name}: ${tool.description}');
    }
    if (_outputSchema != null) {
      buffer.writeln('\nYour output must conform to this schema:');
      buffer.writeln(jsonEncode(_outputSchema!.fields));
    }
    return buffer.toString();
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await _history.dispose();
    _logger.info('Agent disposed');
  }
}

class _AgentBuilder {
  final dynamic _model;
  MurmurationConfig? _config;
  ImmutableState? _state;
  MessageHistory? _history;
  final List<Tool> _tools = [];
  final Map<String, FunctionHandler> _functions = {};
  OutputSchema? _outputSchema;
  int _currentIndex = 0;
  int _totalAgents = 1;
  ProgressCallback? _onProgress;

  _AgentBuilder(this._model);

  _AgentBuilder withConfig(MurmurationConfig config) {
    _config = config;
    return this;
  }

  _AgentBuilder withState(ImmutableState state) {
    _state = state;
    return this;
  }

  _AgentBuilder withStateMap(Map<String, dynamic> stateMap) {
    _state = ImmutableState(initialData: stateMap);
    return this;
  }

  _AgentBuilder withHistory(MessageHistory history) {
    _history = history;
    return this;
  }

  _AgentBuilder withTool(Tool tool) {
    _tools.add(tool);
    return this;
  }

  _AgentBuilder withFunction(String name, FunctionHandler handler) {
    _functions[name] = handler;
    return this;
  }

  _AgentBuilder withOutputSchema(OutputSchema schema) {
    _outputSchema = schema;
    return this;
  }

  _AgentBuilder withIndex(int currentIndex, int totalAgents) {
    _currentIndex = currentIndex;
    _totalAgents = totalAgents;
    return this;
  }

  _AgentBuilder withProgressCallback(ProgressCallback callback) {
    _onProgress = callback;
    return this;
  }

  _AgentBuilder withProgress({
    required int current,
    required int total,
    ProgressCallback? callback,
  }) {
    _currentIndex = current;
    _totalAgents = total;
    _onProgress = callback;
    return this;
  }

  Future<Agent> build() async {
    if (_config == null) {
      throw InvalidConfigurationException(
        'Configuration is required',
        errorDetails: {'provider': LLMProvider.openai.name},
      );
    }
    if (_state == null) {
      throw InvalidConfigurationException(
        'State is required',
        errorDetails: {'provider': LLMProvider.openai.name},
      );
    }
    if (_history == null) {
      _history = MessageHistory(
        threadId: _config!.threadId ?? DateTime.now().toIso8601String(),
        maxMessages: _config!.maxMessages,
        maxTokens: _config!.maxTokens,
      );
    }
    return Agent._internal(
      model: _model,
      config: _config!,
      state: _state!,
      history: _history!,
      tools: _tools,
      functions: _functions,
      outputSchema: _outputSchema,
      currentIndex: _currentIndex,
      totalAgents: _totalAgents,
      onProgress: _onProgress,
    );
  }
}
