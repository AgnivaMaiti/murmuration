import 'dart:async';
import '../agent.dart';
import '../../tools/tool.dart';
import '../../exceptions.dart';
import '../../messaging/message.dart';
import '../../state/immutable_state.dart';

typedef AgentFactory = Future<Agent> Function(AgentContext context);

typedef CoordinationCallback = Future<void> Function(
  AgentContext context,
  AgentProgress progress,
);

class AgentContext {
  final ImmutableState state;
  final List<Message> messageHistory;
  final Map<String, dynamic> sharedData;
  final Map<String, dynamic> localData;

  AgentContext({
    required this.state,
    required this.messageHistory,
    Map<String, dynamic>? sharedData,
    Map<String, dynamic>? localData,
  })  : sharedData = sharedData ?? {},
        localData = localData ?? {};
}

class CoordinationPatterns {
  /// Implements a sequential workflow where agents process data in a pipeline
  static Future<AgentResult> pipeline({
    required List<AgentFactory> agentFactories,
    required AgentContext initialContext,
    ProgressCallback? onProgress,
  }) async {
    AgentContext currentContext = initialContext;
    AgentResult? lastResult;

    for (int i = 0; i < agentFactories.length; i++) {
      final agent = await agentFactories[i](currentContext);
      
      await onProgress?.call(AgentProgress(
        current: i + 1,
        total: agentFactories.length,
        status: 'Executing agent ${i + 1}/${agentFactories.length}',
      ));

      lastResult = await agent.process(
        currentContext.messageHistory.last.content,
        context: currentContext.localData,
      );

      currentContext = AgentContext(
        state: currentContext.state,
        messageHistory: [...currentContext.messageHistory, Message(
          role: MessageRole.assistant,
          content: lastResult.content,
          metadata: {
            'agent_index': i,
            'agent_type': agent.runtimeType.toString(),
          },
        )],
        sharedData: {
          ...currentContext.sharedData,
          ...?lastResult.context?['shared_data'],
        },
      );
    }

    return lastResult!;
  }

  /// Implements a broadcast pattern where multiple agents process the same input
  static Future<List<AgentResult>> broadcast({
    required List<AgentFactory> agentFactories,
    required AgentContext context,
    ProgressCallback? onProgress,
  }) async {
    final results = <AgentResult>[];
    final futures = <Future>[];
    
    for (int i = 0; i < agentFactories.length; i++) {
      final agent = await agentFactories[i](context);
      
      futures.add(agent.process(
        context.messageHistory.last.content,
        context: context.localData,
      ).then((result) {
        onProgress?.call(AgentProgress(
          current: results.length + 1,
          total: agentFactories.length,
          status: 'Completed agent ${results.length + 1}/${agentFactories.length}',
        ));
        results.add(result);
      }));
    }

    await Future.wait(futures);
    return results;
  }

  /// Implements a map-reduce pattern for parallel processing
  static Future<AgentResult> mapReduce({
    required AgentFactory mapperFactory,
    required AgentFactory reducerFactory,
    required List<dynamic> items,
    required AgentContext initialContext,
    ProgressCallback? onProgress,
  }) async {
    // Map phase
    final mapResults = await broadcast(
      agentFactories: List.generate(items.length, (i) => mapperFactory),
      context: initialContext,
      onProgress: onProgress != null 
          ? (progress) => onProgress(progress.copyWith(
                status: 'Mapping (${progress.current}/${progress.total})',
              ))
          : null,
    );

    // Prepare reduce context
    final reduceContext = AgentContext(
      state: initialContext.state,
      messageHistory: [
        ...initialContext.messageHistory,
        Message(
          role: MessageRole.user,
          content: 'Combine these results: ${mapResults.map((r) => r.content).toList()}',
        ),
      ],
      sharedData: {
        ...initialContext.sharedData,
        'map_results': mapResults.map((r) => r.content).toList(),
      },
    );

    // Reduce phase
    final reducer = await reducerFactory(reduceContext);
    return reducer.process(
      'Combine these results',
      context: reduceContext.localData,
    );
  }

  /// Implements a supervisor-worker pattern
  static Future<AgentResult> supervisorWorker({
    required AgentFactory supervisorFactory,
    required Map<String, AgentFactory> workerFactories,
    required AgentContext initialContext,
    ProgressCallback? onProgress,
  }) async {
    final supervisor = await supervisorFactory(initialContext);
    
    while (true) {
      final decision = await supervisor.process(
        initialContext.messageHistory.last.content,
        context: initialContext.localData,
      );

      final decisionData = decision.context?['decision'];
      if (decisionData == 'COMPLETE') {
        return decision;
      }

      final workerType = decisionData?['worker'];
      if (workerType == null || !workerFactories.containsKey(workerType)) {
        throw MurmurationException('Invalid worker type: $workerType');
      }

      final worker = await workerFactories[workerType]!(initialContext);
      final workerResult = await worker.process(
        decisionData['task'],
        context: initialContext.localData,
      );

      // Update context with worker result
      initialContext = AgentContext(
        state: initialContext.state,
        messageHistory: [
          ...initialContext.messageHistory,
          Message(
            role: MessageRole.assistant,
            content: workerResult.content,
            metadata: {'worker': workerType, 'result': workerResult.context},
          ),
        ],
        sharedData: {
          ...initialContext.sharedData,
          ...?workerResult.context?['shared_data'],
        },
      );

      await onProgress?.call(const AgentProgress(
        current: 1,
        total: 1,
        status: 'Worker completed task',
      ));
    }
  }
}
