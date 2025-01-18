class AgentResult {
  final String output;
  final Map<String, dynamic> stateVariables;
  final Stream<String>? stream;

  AgentResult({
    required this.output,
    required this.stateVariables,
    this.stream,
  });
}
