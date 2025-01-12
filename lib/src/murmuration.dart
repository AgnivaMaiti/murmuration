import 'package:google_generative_ai/google_generative_ai.dart';
import 'murmuration_config.dart';
import 'agent.dart';
import 'models.dart';
import 'types.dart';

// Main class
class Murmuration {
  final MurmurationConfig config;
  final GenerativeModel _model;

  Murmuration(this.config)
      : _model = GenerativeModel(
          model: config.model,
          apiKey: config.apiKey,
        );

  // Create an agent
  Agent createAgent(
    Map<String, dynamic> instructions, {
    int currentAgentIndex = 1,
    int totalAgents = 1,
    ProgressCallback? onProgress,
  }) {
    return Agent(
      _model,
      instructions,
      stream: config.stream,
      logger: config.logger,
      currentAgentIndex: currentAgentIndex,
      totalAgents: totalAgents,
      onProgress: onProgress,
    );
  }

  // Run an agent
  Future<AgentResult> run({
    required String input,
    Map<String, dynamic> stateVariables = const {},
    Map<String, dynamic> agentInstructions = const {},
    List<MurmurationTool> tools = const [],
    Map<String, FunctionHandler> functions = const {},
    ProgressCallback? onProgress,
  }) async {
    final agent = createAgent(agentInstructions, onProgress: onProgress);

    for (final entry in functions.entries) {
      agent.registerFunction(entry.key, entry.value);
    }

    agent.updateState({
      ...stateVariables,
      'context_variables': stateVariables,
    });

    for (final tool in tools) {
      agent.registerTool(tool);
    }

    if (config.debug) {
      config.logger.log('Running agent with input: $input');
      config.logger.log('State variables: $stateVariables');
    }

    return await agent.execute(input);
  }

  // Run an agent chain
  Future<ChainResult> runAgentChain({
    required String input,
    required List<Map<String, dynamic>> agentInstructions,
    List<MurmurationTool> tools = const [],
    Map<String, FunctionHandler> functions = const {},
    bool logProgress = false,
    ProgressCallback? onProgress,
  }) async {
    final progressRecords = <AgentProgress>[];
    final results = <AgentResult>[];
    String currentInput = input;

    for (var i = 0; i < agentInstructions.length; i++) {
      final agent = createAgent(
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

      if (i == 0) {
        for (final tool in tools) {
          agent.registerTool(tool);
        }
        for (final entry in functions.entries) {
          agent.registerFunction(entry.key, entry.value);
        }
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
