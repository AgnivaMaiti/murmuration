import 'agent_result.dart';
import 'agent_progress.dart';

class ChainResult {
  final List<AgentResult> results;
  final String finalOutput;
  final List<AgentProgress> progress;

  ChainResult({
    required this.results,
    required this.finalOutput,
    required this.progress,
  });
}
