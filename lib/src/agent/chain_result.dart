import 'agent_progress.dart';
import 'agent_result.dart';

class ChainResult {
  final List<AgentResult> results;
  final String finalOutput;
  final List<AgentProgress> progress;
  final DateTime timestamp;

  ChainResult({
    required this.results,
    required this.finalOutput,
    required this.progress,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'results': results.map((r) => r.toJson()).toList(),
      'finalOutput': finalOutput,
      'progress': progress.map((p) => p.toJson()).toList(),
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ChainResult.fromJson(Map<String, dynamic> json) {
    return ChainResult(
      results: (json['results'] as List<dynamic>)
          .map((r) => AgentResult.fromJson(r))
          .toList(),
      finalOutput: json['finalOutput'] as String,
      progress: (json['progress'] as List<dynamic>)
          .map((p) => AgentProgress.fromJson(p))
          .toList(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  ChainResult copyWith({
    List<AgentResult>? results,
    String? finalOutput,
    List<AgentProgress>? progress,
    DateTime? timestamp,
  }) {
    return ChainResult(
      results: results ?? this.results,
      finalOutput: finalOutput ?? this.finalOutput,
      progress: progress ?? this.progress,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() {
    return 'ChainResult(results: ${results.length}, finalOutput: $finalOutput)';
  }
}
