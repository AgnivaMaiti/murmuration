enum AgentStatus {
  initializing,
  processing,
  postProcessing,
  completed,
  error
}

class AgentProgress {
  final AgentStatus status;
  final int currentAgent;
  final int totalAgents;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  const AgentProgress({
    required this.status,
    required this.currentAgent,
    required this.totalAgents,
    required this.timestamp,
    this.metadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'currentAgent': currentAgent,
      'totalAgents': totalAgents,
      'timestamp': timestamp.toIso8601String(),
      if (metadata != null) 'metadata': metadata,
    };
  }

  factory AgentProgress.fromJson(Map<String, dynamic> json) {
    return AgentProgress(
      status: AgentStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => AgentStatus.error,
      ),
      currentAgent: json['currentAgent'] as int,
      totalAgents: json['totalAgents'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() {
    return 'AgentProgress(status: $status, agent: $currentAgent/$totalAgents)';
  }
}

typedef ProgressCallback = void Function(AgentProgress);
