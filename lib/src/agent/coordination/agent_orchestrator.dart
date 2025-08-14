import 'dart:async';
import 'dart:convert';
import 'package:collection/collection.dart';
import '../agent.dart';
import '../../tools/tool.dart';
import '../../exceptions.dart';
import '../../messaging/message.dart';
import '../../state/immutable_state.dart';
import 'coordination_patterns.dart';

class AgentOrchestrator {
  final Map<String, AgentFactory> _agentRegistry = {};
  final Map<String, Tool> _toolRegistry = {};
  final ImmutableState _globalState;
  final Map<String, dynamic> _sharedContext = {};
  final Map<String, dynamic> _agentStates = {};
  
  /// Maximum number of steps before timing out a workflow
  final int maxWorkflowSteps;
  
  /// Timeout for the entire workflow
  final Duration workflowTimeout;

  AgentOrchestrator({
    required ImmutableState initialState,
    this.maxWorkflowSteps = 100,
    this.workflowTimeout = const Duration(minutes: 30),
  }) : _globalState = initialState;

  /// Register an agent factory with a unique name
  void registerAgent(String name, AgentFactory factory) {
    if (_agentRegistry.containsKey(name)) {
      throw MurmurationException('Agent "$name" is already registered');
    }
    _agentRegistry[name] = factory;
  }

  /// Register a tool that will be available to all agents
  void registerTool(Tool tool) {
    _toolRegistry[tool.name] = tool;
  }

  /// Execute a workflow defined by a JSON configuration
  Future<Map<String, dynamic>> executeWorkflow({
    required String workflowName,
    required Map<String, dynamic> input,
    ProgressCallback? onProgress,
  }) async {
    final workflow = _parseWorkflow(workflowName, input);
    final stopwatch = Stopwatch()..start();
    
    try {
      return await _executeWorkflowSteps(
        workflow: workflow,
        input: input,
        onProgress: onProgress,
      ).timeout(workflowTimeout);
    } on TimeoutException {
      throw MurmurationException(
        'Workflow "$workflowName" timed out after ${workflowTimeout.inSeconds} seconds',
      );
    } finally {
      stopwatch.stop();
      onProgress?.call(AgentProgress(
        current: 1,
        total: 1,
        status: 'Workflow completed in ${stopwatch.elapsed}',
        isComplete: true,
      ));
    }
  }

  Map<String, dynamic> _parseWorkflow(
    String workflowName, 
    Map<String, dynamic> input,
  ) {
    // In a real implementation, this would parse a workflow definition
    // For now, we'll return a simple sequential workflow
    return {
      'name': workflowName,
      'type': 'sequential',
      'steps': input['steps'] ?? [],
    };
  }

  Future<Map<String, dynamic>> _executeWorkflowSteps({
    required Map<String, dynamic> workflow,
    required Map<String, dynamic> input,
    ProgressCallback? onProgress,
  }) async {
    final steps = List<Map<String, dynamic>>.from(workflow['steps'] ?? []);
    Map<String, dynamic> currentState = {...input};
    
    for (int i = 0; i < steps.length; i++) {
      if (i >= maxWorkflowSteps) {
        throw MurmurationException(
          'Maximum workflow steps ($maxWorkflowSteps) exceeded',
        );
      }

      final step = steps[i];
      final stepType = step['type'] ?? 'agent';
      
      await onProgress?.call(AgentProgress(
        current: i + 1,
        total: steps.length,
        status: 'Executing step ${i + 1}/${steps.length}: ${step['name'] ?? stepType}',
      ));

      switch (stepType) {
        case 'agent':
          currentState = await _executeAgentStep(step, currentState);
          break;
        case 'parallel':
          currentState = await _executeParallelStep(step, currentState);
          break;
        case 'condition':
          currentState = await _executeConditionStep(step, currentState);
          break;
        case 'loop':
          currentState = await _executeLoopStep(step, currentState);
          break;
        default:
          throw MurmurationException('Unknown step type: $stepType');
      }
      
      // Update shared context with step results
      if (step['outputKey'] != null) {
        _sharedContext[step['outputKey']] = currentState['result'];
      }
    }
    
    return {
      'success': true,
      'output': currentState,
      'sharedContext': _sharedContext,
    };
  }

  Future<Map<String, dynamic>> _executeAgentStep(
    Map<String, dynamic> step,
    Map<String, dynamic> state,
  ) async {
    final agentName = step['agent'];
    if (!_agentRegistry.containsKey(agentName)) {
      throw MurmurationException('Agent "$agentName" is not registered');
    }

    final agent = await _agentRegistry[agentName]!(AgentContext(
      state: _globalState,
      messageHistory: [
        Message(
          role: MessageRole.user,
          content: step['input'] is String 
              ? step['input'] 
              : jsonEncode(step['input']),
        ),
      ],
      sharedData: _sharedContext,
      localData: {
        ...state,
        'step': step,
      },
    ));

    final result = await agent.process(
      step['input'] is String ? step['input'] : jsonEncode(step['input']),
      context: state,
    );

    return {
      ...state,
      'result': result.content,
      'metadata': {
        ...?state['metadata'],
        'agent': agentName,
        'executionTime': DateTime.now().toIso8601String(),
      },
    };
  }

  Future<Map<String, dynamic>> _executeParallelStep(
    Map<String, dynamic> step,
    Map<String, dynamic> state,
  ) async {
    final steps = List<Map<String, dynamic>>.from(step['steps'] ?? []);
    final results = <String, dynamic>{};
    
    await Future.wait(
      steps.map((s) async {
        final result = await _executeWorkflowSteps(
          workflow: {'steps': [s]},
          input: state,
        );
        if (s['outputKey'] != null) {
          results[s['outputKey']] = result['output']['result'];
        }
      }),
    );

    return {
      ...state,
      'result': results,
    };
  }

  Future<Map<String, dynamic>> _executeConditionStep(
    Map<String, dynamic> step,
    Map<String, dynamic> state,
  ) async {
    final condition = step['condition'];
    bool shouldExecute;
    
    if (condition is Map) {
      // Evaluate condition expression
      // This is a simplified example - in a real implementation, you'd want
      // a full expression evaluator
      final left = _resolveValue(condition['left'], state);
      final right = _resolveValue(condition['right'], state);
      final op = condition['operator'];
      
      switch (op) {
        case '==':
          shouldExecute = left == right;
          break;
        case '!=':
          shouldExecute = left != right;
          break;
        case '>':
          shouldExecute = left > right;
          break;
        case '<':
          shouldExecute = left < right;
          break;
        case '>=':
          shouldExecute = left >= right;
          break;
        case '<=':
          shouldExecute = left <= right;
          break;
        case 'contains':
          shouldExecute = left.toString().contains(right.toString());
          break;
        default:
          throw MurmurationException('Unknown operator: $op');
      }
    } else if (condition is bool) {
      shouldExecute = condition;
    } else {
      throw MurmurationException('Invalid condition: $condition');
    }

    if (shouldExecute) {
      return _executeWorkflowSteps(
        workflow: {'steps': step['then'] ?? []},
        input: state,
      );
    } else if (step['else'] != null) {
      return _executeWorkflowSteps(
        workflow: {'steps': step['else'] ?? []},
        input: state,
      );
    }
    
    return state;
  }

  Future<Map<String, dynamic>> _executeLoopStep(
    Map<String, dynamic> step,
    Map<String, dynamic> state,
  ) async {
    final items = _resolveValue(step['items'], state);
    if (items is! Iterable) {
      throw MurmurationException('Loop items must be an iterable');
    }
    
    final results = [];
    final itemList = items.toList();
    
    for (int i = 0; i < itemList.length; i++) {
      final item = itemList[i];
      final itemState = {
        ...state,
        'item': item,
        'index': i,
        'isFirst': i == 0,
        'isLast': i == itemList.length - 1,
      };
      
      final result = await _executeWorkflowSteps(
        workflow: {'steps': step['steps'] ?? []},
        input: itemState,
      );
      
      results.add(result['output']);
    }
    
    return {
      ...state,
      'result': results,
    };
  }

  dynamic _resolveValue(dynamic value, Map<String, dynamic> state) {
    if (value is String && value.startsWith('\$')) {
      // Resolve variable reference (e.g., "$input.someField")
      final path = value.substring(1).split('.');
      dynamic current = state;
      
      for (final key in path) {
        if (current is Map && current.containsKey(key)) {
          current = current[key];
        } else {
          throw MurmurationException('Could not resolve variable: $value');
        }
      }
      
      return current;
    }
    
    return value;
  }

  /// Get the current state of a specific agent
  Map<String, dynamic>? getAgentState(String agentName) {
    return Map.unmodifiable(_agentStates[agentName] ?? {});
  }

  /// Update the state of a specific agent
  void updateAgentState(String agentName, Map<String, dynamic> state) {
    _agentStates[agentName] = {
      ..._agentStates[agentName] ?? {},
      ...state,
      'lastUpdated': DateTime.now().toIso8601String(),
    };
  }

  /// Get the shared context
  Map<String, dynamic> get sharedContext => Map.unmodifiable(_sharedContext);
  
  /// Get the global state
  ImmutableState get globalState => _globalState;
}
