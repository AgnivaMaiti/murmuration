import 'dart:async';
import 'dart:convert';
import 'package:murmuration/src/exceptions.dart';
import 'immutable_state.dart';

class StateSynchronizer {
  final ImmutableState _globalState;
  final Map<String, StreamController<Map<String, dynamic>>> _stateStreams = {};
  final Map<String, Map<String, dynamic>> _localStates = {};
  final Map<String, Set<String>> _subscriptions = {};
  final Map<String, Set<String>> _reverseSubscriptions = {};
  
  /// Timeout for state synchronization operations
  final Duration _syncTimeout;
  
  /// Conflict resolution strategy
  final ConflictResolutionStrategy conflictResolutionStrategy;

  StateSynchronizer({
    required ImmutableState initialState,
    this.conflictResolutionStrategy = ConflictResolutionStrategy.preferNewer,
    Duration? syncTimeout,
  })  : _globalState = initialState,
        _syncTimeout = syncTimeout ?? const Duration(seconds: 5);

  /// Get a stream of state updates for a specific key
  Stream<Map<String, dynamic>> watchState(String key) {
    _stateStreams[key] ??= StreamController<Map<String, dynamic>>.broadcast();
    return _stateStreams[key]!.stream;
  }

  /// Update a specific state key and notify subscribers
  Future<void> updateState({
    required String key,
    required Map<String, dynamic> newState,
    String? sourceAgent,
  }) async {
    final currentState = _localStates[key] ?? {};
    final mergedState = await _resolveConflicts(
      key: key,
      currentState: currentState,
      newState: newState,
      sourceAgent: sourceAgent,
    );

    _localStates[key] = mergedState;
    _stateStreams[key]?.add(mergedState);
    
    // Notify subscribers
    if (_reverseSubscriptions.containsKey(key)) {
      for (final subscriber in _reverseSubscriptions[key]!) {
        _stateStreams[subscriber]?.add(await getState(subscriber));
      }
    }
  }

  /// Get the current state for a key
  Future<Map<String, dynamic>> getState(String key) async {
    return _localStates[key] ?? {};
  }

  /// Subscribe to state changes from another key
  void subscribe({
    required String subscriberKey,
    required String targetKey,
  }) {
    _subscriptions[subscriberKey] ??= {};
    _subscriptions[subscriberKey]!.add(targetKey);
    
    _reverseSubscriptions[targetKey] ??= {};
    _reverseSubscriptions[targetKey]!.add(subscriberKey);
  }

  /// Unsubscribe from state changes
  void unsubscribe({
    required String subscriberKey,
    String? targetKey,
  }) {
    if (targetKey != null) {
      _subscriptions[subscriberKey]?.remove(targetKey);
      _reverseSubscriptions[targetKey]?.remove(subscriberKey);
    } else {
      final targets = _subscriptions[subscriberKey]?.toList() ?? [];
      for (final target in targets) {
        _reverseSubscriptions[target]?.remove(subscriberKey);
      }
      _subscriptions.remove(subscriberKey);
    }
  }

  /// Merge states based on the configured conflict resolution strategy
  Future<Map<String, dynamic>> _resolveConflicts({
    required String key,
    required Map<String, dynamic> currentState,
    required Map<String, dynamic> newState,
    String? sourceAgent,
  }) async {
    if (currentState.isEmpty) return newState;
    if (newState.isEmpty) return currentState;

    switch (conflictResolutionStrategy) {
      case ConflictResolutionStrategy.preferNewer:
        return _mergeWithNewerPrecedence(currentState, newState);
      case ConflictResolutionStrategy.preferOlder:
        return _mergeWithOlderPrecedence(currentState, newState);
      case ConflictResolutionStrategy.merge:
        return _deepMerge(currentState, newState);
      case ConflictResolutionStrategy.custom:
        return await _customMerge(
          key: key,
          currentState: currentState,
          newState: newState,
          sourceAgent: sourceAgent,
        );
    }
  }

  /// Merge with newer values taking precedence
  Map<String, dynamic> _mergeWithNewerPrecedence(
    Map<String, dynamic> current,
    Map<String, dynamic> newer,
  ) {
    return _deepMerge(current, newer);
  }

  /// Merge with older values taking precedence
  Map<String, dynamic> _mergeWithOlderPrecedence(
    Map<String, dynamic> older,
    Map<String, dynamic> newer,
  ) {
    return _deepMerge(newer, older);
  }

  /// Deep merge two maps
  Map<String, dynamic> _deepMerge(
    Map<String, dynamic> map1,
    Map<String, dynamic> map2,
  ) {
    final result = Map<String, dynamic>.from(map1);
    
    map2.forEach((key, value) {
      if (value is Map<String, dynamic> && 
          result[key] is Map<String, dynamic>) {
        result[key] = _deepMerge(
          result[key] as Map<String, dynamic>,
          value,
        );
      } else {
        result[key] = value;
      }
    });
    
    return result;
  }

  /// Custom merge implementation that can be overridden by subclasses
  Future<Map<String, dynamic>> _customMerge({
    required String key,
    required Map<String, dynamic> currentState,
    required Map<String, dynamic> newState,
    String? sourceAgent,
  }) async {
    // Default implementation uses deep merge
    return _deepMerge(currentState, newState);
  }

  /// Persist the current state to storage
  Future<void> persistState(String key) async {
    final state = _localStates[key];
    if (state != null) {
      await _globalState.set(key, jsonEncode(state));
    }
  }

  /// Load state from storage
  Future<void> loadState(String key) async {
    final stateJson = await _globalState.get(key);
    if (stateJson != null) {
      _localStates[key] = Map<String, dynamic>.from(
        jsonDecode(stateJson) as Map,
      );
    }
  }

  /// Synchronize state with a remote source
  Future<bool> synchronize({
    required String key,
    required Future<Map<String, dynamic>> Function() remoteFetch,
    required Future<void> Function(Map<String, dynamic>) remoteUpdate,
    bool force = false,
  }) async {
    try {
      final localState = _localStates[key] ?? {};
      final remoteState = await remoteFetch().timeout(_syncTimeout);
      
      if (!force && _isStateEqual(localState, remoteState)) {
        return true; // Already in sync
      }
      
      final mergedState = await _resolveConflicts(
        key: key,
        currentState: localState,
        newState: remoteState,
      );
      
      // Update remote with merged state
      await remoteUpdate(mergedState).timeout(_syncTimeout);
      
      // Update local state
      _localStates[key] = mergedState;
      _stateStreams[key]?.add(mergedState);
      
      return true;
    } on TimeoutException {
      throw StateSynchronizationException(
        'State synchronization timed out for key: $key',
      );
    } catch (e) {
      throw StateSynchronizationException(
        'Failed to synchronize state: $e',
      );
    }
  }

  /// Check if two states are equal
  bool _isStateEqual(
    Map<String, dynamic> state1,
    Map<String, dynamic> state2,
  ) {
    return const MapEquality().equals(state1, state2);
  }

  /// Get all state keys
  Set<String> get stateKeys => _localStates.keys.toSet();

  /// Clear all state (for testing)
  @visibleForTesting
  void clear() {
    _localStates.clear();
    for (final controller in _stateStreams.values) {
      controller.close();
    }
    _stateStreams.clear();
    _subscriptions.clear();
    _reverseSubscriptions.clear();
  }
}

/// Strategy for resolving state conflicts
enum ConflictResolutionStrategy {
  preferNewer,  // Newer values take precedence
  preferOlder,  // Older values take precedence
  merge,        // Deep merge all values
  custom,       // Use custom merge logic
}

/// Exception thrown when state synchronization fails
class StateSynchronizationException extends MurmurationException {
  StateSynchronizationException(String message) : super(message);
}
