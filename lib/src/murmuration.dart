import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:synchronized/synchronized.dart';
import 'dart:async';
import '../../murmuration.dart';

class Murmuration {
  final MurmurationConfig config;
  final GenerativeModel _model;
  final Lock _lock = Lock();

  Murmuration(this.config)
      : _model = GenerativeModel(
          model: config.model,
          apiKey: config.apiKey,
        );

  Future<Agent> createAgent(
    Map<String, dynamic> instructions, {
    int currentAgentIndex = 1,
    int totalAgents = 1,
    ProgressCallback? onProgress,
  }) async {
    return await Agent.builder(_model)
        .withState(instructions)
        .withConfig(config)
        .withProgress(
          current: currentAgentIndex,
          total: totalAgents,
          callback: onProgress,
        )
        .build();
  }

  Future<void> clearHistory(String threadId) async {
    await _lock.synchronized(() async {
      final history = MessageHistory(threadId: threadId);
      await history.clear();
    });
  }

  Future<ChainResult> runAgentChain({
    required String input,
    required List<Map<String, dynamic>> agentInstructions,
    List<Tool> tools = const [],
    Map<String, FunctionHandler> functions = const {},
    bool logProgress = false,
    ProgressCallback? onProgress,
  }) async {
    final progressRecords = <AgentProgress>[];
    final results = <AgentResult>[];
    String currentInput = input;

    for (var i = 0; i < agentInstructions.length; i++) {
      final agent = await createAgent(
        agentInstructions[i],
        currentAgentIndex: i + 1,
        totalAgents: agentInstructions.length,
        onProgress: (progress) {
          if (logProgress) {
            progressRecords.add(progress);
            onProgress?.call(progress);
          }
        },
      );

      for (final tool in tools) {
        agent.addTool(tool);
      }

      for (final entry in functions.entries) {
        agent.addFunction(entry.key, entry.value);
      }

      final result = await agent.execute(currentInput);
      results.add(result);

      if (result.stream != null) {
        await for (final chunk in result.stream!) {
          currentInput = chunk;
        }
      } else {
        currentInput = result.output;
      }
    }

    return ChainResult(
      results: results,
      finalOutput: currentInput,
      progress: progressRecords,
    );
  }
}
