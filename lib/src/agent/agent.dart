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

  static Future<Agent> builder(dynamic model) async {
    return _AgentBuilder(model).build();
  }

  void addTool(Tool tool) {
    if (_isDisposed) {
      throw StateException('Agent has been disposed');
    }
    _tools.add(tool);
  }

  void addFunction(String name, FunctionHandler handler) {
    if (_isDisposed) {
      throw StateException('Agent has been disposed');
    }
    _functions[name] = handler;
  }

  @override
  Future<AgentResult> execute(String input) async {
    if (_isDisposed) {
      throw StateException('Agent has been disposed');
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
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _validateInput(String input) async {
    if (input.isEmpty) {
      throw ValidationException(
        'Input cannot be empty',
        errorDetails: {'input': input},
      );
    }

    if (input.length > _config.maxTokens) {
      throw TokenLimitException(
        'Input exceeds maximum token limit',
        errorDetails: {
          'inputLength': input.length,
          'maxTokens': _config.maxTokens,
        },
      );
    }
  }

  Future<List<Message>> _prepareMessages(String input) async {
    final messages = <Message>[];

    // Add system message if available
    final systemMessage = _state.get<String>('systemMessage');
    if (systemMessage != null) {
      messages.add(Message(
        role: MessageRole.system,
        content: systemMessage,
      ));
    }

    // Add context from state if available
    final context = _state.get<Map<String, dynamic>>('context');
    if (context != null) {
      messages.add(Message(
        role: MessageRole.system,
        content: 'Context: ${jsonEncode(context)}',
      ));
    }

    // Add history messages
    messages.addAll(_history.messages);

    // Add current input
    messages.add(Message(
      role: MessageRole.user,
      content: input,
    ));

    return messages;
  }

  Future<Map<String, dynamic>> _getModelResponse(List<Message> messages) async {
    try {
      final response = await _model.chatCompletion(
        messages: messages,
        stream: _config.stream,
        functions: _prepareFunctions(),
        functionCall: _determineFunctionCall(),
      );

      if (response['choices'] == null || response['choices'].isEmpty) {
        throw MurmurationException(
          'Invalid response format from model',
          code: ErrorCode.invalidResponse,
          errorDetails: {'response': response},
        );
      }

      return response;
    } catch (e, stackTrace) {
      throw MurmurationException(
        'Failed to get model response: $e',
        code: ErrorCode.unknownError,
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  Map<String, dynamic>? _prepareFunctions() {
    if (_functions.isEmpty) return null;

    return {
      for (final entry in _functions.entries)
        entry.key: {
          'name': entry.key,
          'description':
              _state.get<String>('function_${entry.key}_description') ?? '',
          'parameters': _state.get<Map<String, dynamic>>(
                  'function_${entry.key}_parameters') ??
              {},
        }
    };
  }

  String? _determineFunctionCall() {
    if (_functions.isEmpty) return null;
    return _state.get<String>('function_call') ?? 'auto';
  }

  Future<AgentResult> _processResponse(Map<String, dynamic> response) async {
    final choice = response['choices'][0];
    final message = choice['message'];
    final functionCall = message['function_call'];

    if (functionCall != null) {
      return await _handleFunctionCall(functionCall);
    }

    final content = message['content'] as String;
    if (_outputSchema != null) {
      return await _validateAndFormatOutput(content);
    }

    return AgentResult(
      output: content,
      metadata: {
        'model': _config.modelConfig.modelName,
        'usage': response['usage'],
        'finish_reason': choice['finish_reason'],
      },
    );
  }

  Future<AgentResult> _handleFunctionCall(
      Map<String, dynamic> functionCall) async {
    final name = functionCall['name'] as String;
    final parameters = functionCall['arguments'] as Map<String, dynamic>;
    final handler = _functions[name];

    if (handler == null) {
      throw MurmurationException(
        'Unknown function: $name',
        code: ErrorCode.unknownError,
        errorDetails: {'function': name},
      );
    }

    try {
      final result = await handler(parameters);
      return AgentResult(
        output: result,
        metadata: {
          'function': name,
          'parameters': parameters,
        },
      );
    } catch (e, stackTrace) {
      throw MurmurationException(
        'Failed to execute function $name: $e',
        code: ErrorCode.unknownError,
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<AgentResult> _validateAndFormatOutput(String content) async {
    try {
      final data = jsonDecode(content);
      final result = _outputSchema!.validateAndConvert(data);

      if (!result.isSuccess) {
        throw ValidationException(
          'Output validation failed: ${result.error}',
          code: ErrorCode.validationError,
          errorDetails: {'content': content},
        );
      }

      return AgentResult(
        output: jsonEncode(result.value),
        metadata: {
          'model': _config.modelConfig.modelName,
          'schema': _outputSchema.toString(),
        },
      );
    } catch (e, stackTrace) {
      throw ValidationException(
        'Failed to validate output: $e',
        code: ErrorCode.validationError,
        errorDetails: {'content': content},
        stackTrace: stackTrace,
      );
    }
  }

  void _handleError(dynamic error, StackTrace? stackTrace) {
    if (error is MurmurationException) {
      _logger.error(
        'Agent execution failed',
        error,
        stackTrace,
        {
          'agentIndex': _currentIndex,
          'totalAgents': _totalAgents,
          'state': _state.toMap(),
        },
      );
    } else {
      _logger.error(
        'Unexpected error during agent execution',
        error,
        stackTrace,
        {
          'agentIndex': _currentIndex,
          'totalAgents': _totalAgents,
          'state': _state.toMap(),
        },
      );
    }
  }

  void _updateProgress(AgentStatus status) {
    if (_onProgress != null) {
      _onProgress!(AgentProgress(
        status: status,
        currentAgent: _currentIndex,
        totalAgents: _totalAgents,
        timestamp: DateTime.now(),
      ));
    }
  }

  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;
    _tools.clear();
    _functions.clear();
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
  int _currentIndex = 1;
  int _totalAgents = 1;
  ProgressCallback? _onProgress;

  _AgentBuilder(this._model);

  _AgentBuilder withConfig(MurmurationConfig config) {
    _config = config;
    return this;
  }

  _AgentBuilder withState(Map<String, dynamic> state) {
    _state = ImmutableState(initialData: state);
    return this;
  }

  _AgentBuilder withHistory(MessageHistory history) {
    _history = history;
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

  _AgentBuilder withOutputSchema(OutputSchema schema) {
    _outputSchema = schema;
    return this;
  }

  Future<Agent> build() async {
    if (_config == null) {
      throw InvalidConfigurationException('Configuration is required');
    }

    if (_state == null) {
      throw InvalidConfigurationException('State is required');
    }

    if (_history == null) {
      _history = MessageHistory(
        threadId: _config!.threadId ??
            DateTime.now().millisecondsSinceEpoch.toString(),
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
