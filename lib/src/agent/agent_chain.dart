import 'dart:async';
import '../config/murmuration_config.dart';
import '../exceptions.dart';
import '../logging/logger.dart';
import '../messaging/message.dart';
import '../messaging/message_history.dart';
import '../schema/output_schema.dart';
import '../state/immutable_state.dart';
import 'agent.dart';
import 'agent_progress.dart';
import 'agent_result.dart';
import 'chain_result.dart';

class AgentChain {
  final List<Agent> _agents;
  final MurmurationConfig _config;
  final MurmurationLogger _logger;
  final ImmutableState _state;
  final MessageHistory _history;
  final StreamController<AgentProgress>? _progressController;
  bool _isDisposed = false;

  AgentChain._internal({
    required List<Agent> agents,
    required MurmurationConfig config,
    required ImmutableState state,
    required MessageHistory history,
    StreamController<AgentProgress>? progressController,
  })  : _agents = agents,
        _config = config,
        _logger = config.logger,
        _state = state,
        _history = history,
        _progressController = progressController;

  static Future<AgentChain> builder() async {
    return _ChainBuilder();
  }

  @override
  Future<ChainResult> execute(String input) async {
    if (_isDisposed) {
      throw StateException('Chain has been disposed');
    }

    if (_agents.isEmpty) {
      throw InvalidConfigurationException('Chain must have at least one agent');
    }

    final results = <AgentResult>[];
    final progress = <AgentProgress>[];
    String currentInput = input;

    try {
      for (var i = 0; i < _agents.length; i++) {
        final agent = _agents[i];

        _updateProgress(AgentProgress(
          status: AgentStatus.initializing,
          currentAgent: i + 1,
          totalAgents: _agents.length,
          timestamp: DateTime.now(),
          metadata: {'input': currentInput},
        ));

        try {
          final result = await agent.execute(currentInput);
          results.add(result);
          currentInput = result.output;

          _updateProgress(AgentProgress(
            status: AgentStatus.completed,
            currentAgent: i + 1,
            totalAgents: _agents.length,
            timestamp: DateTime.now(),
            metadata: {'output': result.output},
          ));
        } catch (e, stackTrace) {
          _handleError(e, stackTrace, i + 1);

          _updateProgress(AgentProgress(
            status: AgentStatus.error,
            currentAgent: i + 1,
            totalAgents: _agents.length,
            timestamp: DateTime.now(),
            metadata: {'error': e.toString()},
          ));

          rethrow;
        }
      }

      return ChainResult(
        results: results,
        finalOutput: currentInput,
        progress: progress,
      );
    } finally {
      if (_progressController != null) {
        await _progressController!.close();
      }
    }
  }

  void _updateProgress(AgentProgress update) {
    if (_progressController != null && !_progressController!.isClosed) {
      _progressController!.add(update);
    }
  }

  void _handleError(dynamic error, StackTrace stackTrace, int agentIndex) {
    final errorContext = {
      'agentIndex': agentIndex,
      'totalAgents': _agents.length,
      'state': _state.toMap(),
      'history': _history.messages.map((m) => m.toJson()).toList(),
    };

    if (error is MurmurationException) {
      _logger.error(
        'Chain execution failed at agent $agentIndex',
        error,
        stackTrace,
        errorContext,
      );
    } else {
      _logger.error(
        'Unexpected error during chain execution at agent $agentIndex',
        error,
        stackTrace,
        errorContext,
      );
    }
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    for (final agent in _agents) {
      await agent.dispose();
    }
    _agents.clear();

    if (_progressController != null && !_progressController!.isClosed) {
      await _progressController!.close();
    }
  }
}

class _ChainBuilder {
  final List<Agent> _agents = [];
  MurmurationConfig? _config;
  ImmutableState? _state;
  MessageHistory? _history;
  StreamController<AgentProgress>? _progressController;

  _ChainBuilder();

  _ChainBuilder withConfig(MurmurationConfig config) {
    _config = config;
    return this;
  }

  _ChainBuilder withState(Map<String, dynamic> state) {
    _state = ImmutableState(initialData: state);
    return this;
  }

  _ChainBuilder withHistory(MessageHistory history) {
    _history = history;
    return this;
  }

  _ChainBuilder withProgressStream() {
    _progressController = StreamController<AgentProgress>.broadcast();
    return this;
  }

  _ChainBuilder addAgent(Agent agent) {
    _agents.add(agent);
    return this;
  }

  Future<AgentChain> build() async {
    if (_config == null) {
      throw InvalidConfigurationException('Configuration is required');
    }

    if (_state == null) {
      throw InvalidConfigurationException('State is required');
    }

    if (_history == null) {
      _history = MessageHistory(
        threadId: _config!.threadId ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        maxMessages: _config!.maxMessages,
        maxTokens: _config!.maxTokens,
      );
    }

    return AgentChain._internal(
      agents: _agents,
      config: _config!,
      state: _state!,
      history: _history!,
      progressController: _progressController,
    );
  }
}
