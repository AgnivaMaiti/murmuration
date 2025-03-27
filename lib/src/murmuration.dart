import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:synchronized/synchronized.dart';
import 'dart:async';
import '../../murmuration.dart';
import 'client/openai_client.dart';
import 'exceptions.dart';
import 'agent/agent.dart';
import 'messaging/message_history.dart';
import 'agent/chain_result.dart';
import 'agent/agent_progress.dart';
import 'state/immutable_state.dart';

class Murmuration {
  final MurmurationConfig config;
  final dynamic _model;
  final Lock _lock = Lock();

  Murmuration(this.config) : _model = _initializeModel(config);

  static dynamic _initializeModel(MurmurationConfig config) {
    switch (config.provider) {
      case LLMProvider.google:
        return GenerativeModel(
          model: config.modelConfig.modelName,
          apiKey: config.apiKey,
        );
      case LLMProvider.openai:
        return OpenAIClient(config);
      default:
        throw MurmurationException(
          'Unsupported LLM provider: ${config.provider}',
          code: ErrorCode.invalidProvider,
        );
    }
  }

  Future<Agent> createAgent(
    Map<String, dynamic> instructions, {
    int currentAgentIndex = 1,
    int totalAgents = 1,
    ProgressCallback? onProgress,
  }) async {
    // Create an ImmutableState from the instructions
    final state = ImmutableState(initialData: instructions);
    
    // Use the builder pattern with withState instead of withStateMap
    return await Agent.builder(_model)
        .withState(state)
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
        final buffer = StringBuffer();
        await for (final chunk in result.stream!) {
          buffer.write(chunk);
        }
        currentInput = buffer.toString();
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

  void dispose() {
    if (_model is OpenAIClient) {
      (_model as OpenAIClient).dispose();
    }
  }
}
