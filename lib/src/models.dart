// Class representing the progress of an agent's execution.
class AgentProgress {
  final int currentAgent;
  final int totalAgents;
  final String status;
  final String? output;
  final DateTime timestamp;

  AgentProgress({
    required this.currentAgent,
    required this.totalAgents,
    required this.status,
    this.output,
  }) : timestamp = DateTime.now();

  @override
  String toString() =>
      '[Agent $currentAgent/$totalAgents] $status${output != null ? ': $output' : ''}';
}

// Class representing the result of an agent's execution.
class AgentResult {
  final String output;
  final Map<String, dynamic> stateVariables;
  final List<String> toolCalls;
  final Stream<String>? stream;
  final List<AgentProgress>? progress;

  AgentResult({
    required this.output,
    this.stateVariables = const {},
    this.toolCalls = const [],
    this.stream,
    this.progress,
  });
}

// Class representing the result of a chain of agent executions.
class ChainResult {
  final List<AgentResult> results;
  final String finalOutput;
  final List<AgentProgress> progress;

  ChainResult({
    required this.results,
    required this.finalOutput,
    this.progress = const [],
  });
}

// Class representing a tool call with its parameters.
class ToolCall {
  final String name;
  final Map<String, dynamic> parameters;

  ToolCall(this.name, this.parameters);

  Map<String, dynamic> toJson() => {
        'name': name,
        'parameters': parameters,
      };
}

// Class representing a murmuration tool with execution functionality.
class MurmurationTool {
  final String name;
  final String description;
  final Map<String, dynamic> schema;
  final Function execute;

  MurmurationTool({
    required this.name,
    required this.description,
    required this.schema,
    required this.execute,
  });
}

// Custom error class for handling murmuration-specific errors.
class MurmurationError extends Error {
  final String message;
  final dynamic originalError;

  MurmurationError(this.message, [this.originalError]);

  @override
  String toString() => 'MurmurationError: $message';
}
