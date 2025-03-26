import 'dart:async';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:synchronized/synchronized.dart';
import 'client/openai_client.dart';
import 'config/murmuration_config.dart';
import 'exceptions.dart';
import 'logging/logger.dart';
import 'messaging/message_history.dart';
import 'agent/agent.dart';
import 'agent/agent_result.dart';
import 'agent/chain_result.dart';
import 'agent/agent_progress.dart';

class Murmuration {
  final MurmurationConfig config;
  final dynamic _model;
  final Lock _lock = Lock();
  final Map<String, MessageHistory> _histories = {};
  final Map<String, DateTime> _lastAccess = {};
  final Timer _cleanupTimer;
  bool _isDisposed = false;

  Murmuration(this.config) : _model = _initializeModel(config) {
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _cleanupUnusedHistories(),
    );
  }

  static dynamic _initializeModel(MurmurationConfig config) {
    try {
      switch (config.provider) {
        case LLMProvider.google:
          return GenerativeModel(
            model: config.modelConfig.modelName,
            apiKey: config.apiKey,
          );
        case LLMProvider.openai:
          return OpenAIClient(config);
        case LLMProvider.anthropic:
          throw ModelNotSupportedException(
              'Anthropic provider not yet supported');
        case LLMProvider.custom:
          throw ModelNotSupportedException('Custom provider not yet supported');
      }
    } catch (e, stackTrace) {
      throw InvalidConfigurationException(
        'Failed to initialize model: $e',
        errorDetails: {
          'provider': config.provider.name,
          'model': config.modelConfig.modelName,
        },
        stackTrace: stackTrace,
      );
    }
  }

  Future<Agent> createAgent(
    Map<String, dynamic> instructions, {
    int currentAgentIndex = 1,
    int totalAgents = 1,
    ProgressCallback? onProgress,
  }) async {
    if (_isDisposed) {
      throw StateException('Murmuration instance has been disposed');
    }

    try {
      return await Agent.builder(_model)
          .withState(instructions)
          .withConfig(config)
          .withProgress(
            current: currentAgentIndex,
            total: totalAgents,
            callback: onProgress,
          )
          .build();
    } catch (e, stackTrace) {
      throw MurmurationException(
        'Failed to create agent: $e',
        code: ErrorCode.unknownError,
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> clearHistory(String threadId) async {
    if (_isDisposed) {
      throw StateException('Murmuration instance has been disposed');
    }

    await _lock.synchronized(() async {
      try {
        final history = _histories[threadId];
        if (history != null) {
          await history.clear();
          _histories.remove(threadId);
          _lastAccess.remove(threadId);
        }
      } catch (e, stackTrace) {
        throw MurmurationException(
          'Failed to clear history: $e',
          code: ErrorCode.resourceError,
          originalError: e,
          stackTrace: stackTrace,
        );
      }
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
    if (_isDisposed) {
      throw StateException('Murmuration instance has been disposed');
    }

    final progressRecords = <AgentProgress>[];
    final results = <AgentResult>[];
    String currentInput = input;

    try {
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

        await agent.dispose();
      }

      return ChainResult(
        results: results,
        finalOutput: currentInput,
        progress: progressRecords,
      );
    } catch (e, stackTrace) {
      throw MurmurationException(
        'Failed to run agent chain: $e',
        code: ErrorCode.unknownError,
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  MessageHistory getHistory(String threadId) {
    if (_isDisposed) {
      throw StateException('Murmuration instance has been disposed');
    }

    return _lock.synchronized(() {
      final history = _histories.putIfAbsent(
        threadId,
        () => MessageHistory(
          threadId: threadId,
          maxMessages: config.maxMessages,
          maxTokens: config.maxTokens,
        ),
      );
      _lastAccess[threadId] = DateTime.now();
      return history;
    });
  }

  void _cleanupUnusedHistories() {
    if (_isDisposed) return;

    _lock.synchronized(() {
      final now = DateTime.now();
      final keysToRemove = _lastAccess.entries
          .where((entry) => now.difference(entry.value) > config.cacheTimeout)
          .map((e) => e.key)
          .toList();

      for (final key in keysToRemove) {
        _histories.remove(key);
        _lastAccess.remove(key);
      }
    });
  }

  Future<void> dispose() async {
    if (_isDisposed) return;

    _isDisposed = true;
    _cleanupTimer.cancel();

    await _lock.synchronized(() async {
      for (final history in _histories.values) {
        await history.dispose();
      }
      _histories.clear();
      _lastAccess.clear();

      if (_model is OpenAIClient) {
        await (_model as OpenAIClient).dispose();
      }
    });
  }

  @override
  String toString() {
    return 'Murmuration(provider: ${config.provider}, model: ${config.modelConfig.modelName})';
  }
}
