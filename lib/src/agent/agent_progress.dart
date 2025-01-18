class AgentProgress {
  final int currentAgent;
  final int totalAgents;
  final String status;
  final String? output;

  AgentProgress({
    required this.currentAgent,
    required this.totalAgents,
    required this.status,
    this.output,
  });

  double get progress => currentAgent / totalAgents;

  @override
  String toString() => 'AgentProgress(current: $currentAgent, '
      'total: $totalAgents, '
      'status: $status'
      '${output != null ? ', output: $output' : ''})';
}
