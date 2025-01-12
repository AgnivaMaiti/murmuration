import 'dart:async';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'logger.dart';
import 'models.dart';
import 'types.dart';

// Class representing an agent.
class Agent {
  final GenerativeModel _model;
  final Map<String, dynamic> _instructions;
  final MurmurationLogger _logger;
  final StreamController<AgentProgress>? _progressController;
  final int _currentAgentIndex;
  final int _totalAgents;
  final ProgressCallback? _onProgress;

  Map<String, dynamic> _state = {};
  final List<MurmurationTool> _tools = [];
  final Map<String, FunctionHandler> _functions = {};
  final bool _streamEnabled;

  Agent(
    this._model,
    this._instructions, {
    bool stream = false,
    MurmurationLogger? logger,
    StreamController<AgentProgress>? progressController,
    int currentAgentIndex = 1,
    int totalAgents = 1,
    ProgressCallback? onProgress,
  })  : _streamEnabled = stream,
        _logger = logger ?? const MurmurationLogger(),
        _progressController = progressController,
        _currentAgentIndex = currentAgentIndex,
        _totalAgents = totalAgents,
        _onProgress = onProgress;

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

  void registerFunction(String name, FunctionHandler handler) {
    _functions[name] = handler;
    _logger.log('Registered function: $name');
  }

  void registerTool(MurmurationTool tool) {
    _tools.add(tool);
    _logger.log('Registered tool: ${tool.name}');
  }

  // Hands off state to the next agent.
  Future<void> handoff(Agent nextAgent) async {
    nextAgent._state = {..._state};
    _logger.log('State handed off to next agent');
  }

  void updateState(Map<String, dynamic> newState) {
    _state = {..._state, ...newState};
    _logger.log('State updated: $_state');
  }

  Future<dynamic> _executeFunctionCall(
      String functionName, Map<String, dynamic> params) async {
    if (!_functions.containsKey(functionName)) {
      throw MurmurationError('Function $functionName not found');
    }

    _reportProgress('Executing function', output: functionName);
    final handler = _functions[functionName]!;

    final parameters = Function.apply(handler, [], {
      if (_state.containsKey('context_variables'))
        Symbol('context_variables'): _state['context_variables']
    });

    final result = await parameters(params);

    if (result is Agent) {
      await handoff(result);
      return await result.execute('Continue with transferred context');
    }

    _reportProgress('Function completed', output: result?.toString());
    return result?.toString() ?? '';
  }

  // Streams response from the generative model.
  Stream<String> _streamResponse(String prompt) async* {
    _reportProgress('Starting stream response');
    final content = [Content.text(prompt)];
    final response = await _model.generateContent(content);

    if (response.text != null) {
      for (var chunk in response.text!.split(' ')) {
        _reportProgress('Streaming chunk', output: chunk);
        yield chunk;
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  Future<AgentResult> execute(String input) async {
    _reportProgress('Starting execution', output: input);
    final prompt = _buildPrompt(input);

    if (_streamEnabled) {
      return AgentResult(
        output: '',
        stateVariables: _state,
        stream: _streamResponse(prompt),
      );
    }

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      _reportProgress('Received response', output: response.text);

      final responseText = response.text ?? '';
      if (responseText.contains('function:')) {
        final functionCall = _parseFunctionCall(responseText);
        final result = await _executeFunctionCall(
          functionCall['name'],
          functionCall['parameters'],
        );

        if (result is AgentResult) return result;

        return AgentResult(
          output: result.toString(),
          stateVariables: _state,
        );
      }

      return _processResponse(response);
    } catch (e) {
      _logger.error('Execution error: $e');
      rethrow;
    }
  }

  // Parses a function call from the response text.
  Map<String, dynamic> _parseFunctionCall(String text) {
    final regex = RegExp(r'function:\s*(\w+)\s*\((.*)\)');
    final match = regex.firstMatch(text);
    if (match == null) {
      throw MurmurationError('Invalid function call format');
    }

    final name = match.group(1)!;
    final paramsStr = match.group(2)!;

    final params = Map<String, dynamic>.fromEntries(paramsStr
        .split(',')
        .map((p) => p.trim().split(':'))
        .map((p) => MapEntry(p[0].trim(), p[1].trim())));

    return {
      'name': name,
      'parameters': params,
    };
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
    Instructions: ${_instructions['role']}
    $toolsDescription
    $functionsDescription
    Context: ${_state.toString()}
    Input: $input
    ''';
  }

  // Processes the response from the generative model.
  AgentResult _processResponse(GenerateContentResponse response) {
    return AgentResult(
      output: response.text ?? '',
      stateVariables: _state,
    );
  }
}
