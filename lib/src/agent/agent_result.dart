import 'dart:async';

class AgentResult {
  final String output;
  final Map<String, dynamic>? metadata;
  final Stream<String>? stream;
  final DateTime timestamp;

  AgentResult({
    required this.output,
    this.metadata,
    this.stream,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'output': output,
      if (metadata != null) 'metadata': metadata,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory AgentResult.fromJson(Map<String, dynamic> json) {
    return AgentResult(
      output: json['output'] as String,
      metadata: json['metadata'] as Map<String, dynamic>?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  AgentResult copyWith({
    String? output,
    Map<String, dynamic>? metadata,
    Stream<String>? stream,
    DateTime? timestamp,
  }) {
    return AgentResult(
      output: output ?? this.output,
      metadata: metadata ?? this.metadata,
      stream: stream ?? this.stream,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() {
    return 'AgentResult(output: $output, metadata: $metadata)';
  }
}
