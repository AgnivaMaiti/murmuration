import 'dart:collection';
import '../exceptions.dart';

class ImmutableState {
  final Map<String, dynamic> _data;
  final Map<String, dynamic> _metadata;
  final List<String> _history;
  final int _maxHistorySize;

  ImmutableState({
    Map<String, dynamic>? initialData,
    Map<String, dynamic>? metadata,
    int maxHistorySize = 100,
  })  : _data = UnmodifiableMapView(initialData ?? {}),
        _metadata = UnmodifiableMapView(metadata ?? {}),
        _history = [],
        _maxHistorySize = maxHistorySize;

  ImmutableState._internal(
    this._data,
    this._metadata,
    this._history,
    this._maxHistorySize,
  );

  T? get<T>(String key) {
    final value = _data[key];
    if (value == null) return null;
    if (value is T) return value;
    throw StateException(
      'Type mismatch: Expected $T but got ${value.runtimeType}',
      errorDetails: {'key': key, 'value': value},
    );
  }

  bool hasKey(String key) => _data.containsKey(key);

  bool get isEmpty => _data.isEmpty;

  int get length => _data.length;

  Map<String, dynamic> toMap() => Map.unmodifiable(_data);

  Map<String, dynamic> getMetadata() => Map.unmodifiable(_metadata);

  List<String> getHistory() => List.unmodifiable(_history);

  ImmutableState copyWith({
    Map<String, dynamic>? newData,
    Map<String, dynamic>? newMetadata,
    bool validate = true,
  }) {
    if (newData == null && newMetadata == null) return this;

    final updatedData = Map<String, dynamic>.from(_data);
    final updatedMetadata = Map<String, dynamic>.from(_metadata);
    final updatedHistory = List<String>.from(_history);

    if (newData != null) {
      updatedData.addAll(newData);
      if (validate) {
        _validateData(updatedData);
      }
      _addToHistory('Updated data: ${newData.keys.join(', ')}');
    }

    if (newMetadata != null) {
      updatedMetadata.addAll(newMetadata);
      _addToHistory('Updated metadata: ${newMetadata.keys.join(', ')}');
    }

    return ImmutableState._internal(
      UnmodifiableMapView(updatedData),
      UnmodifiableMapView(updatedMetadata),
      updatedHistory,
      _maxHistorySize,
    );
  }

  ImmutableState merge(ImmutableState other) {
    return copyWith(
      newData: other._data,
      newMetadata: other._metadata,
    );
  }

  ImmutableState remove(String key) {
    if (!_data.containsKey(key)) return this;

    final updatedData = Map<String, dynamic>.from(_data)..remove(key);
    final updatedHistory = List<String>.from(_history);
    _addToHistory('Removed key: $key');

    return ImmutableState._internal(
      UnmodifiableMapView(updatedData),
      UnmodifiableMapView(_metadata),
      updatedHistory,
      _maxHistorySize,
    );
  }

  ImmutableState clear() {
    if (_data.isEmpty) return this;

    final updatedHistory = List<String>.from(_history);
    _addToHistory('Cleared all data');

    return ImmutableState._internal(
      UnmodifiableMapView({}),
      UnmodifiableMapView({}),
      updatedHistory,
      _maxHistorySize,
    );
  }

  void _validateData(Map<String, dynamic> data) {
    for (final entry in data.entries) {
      if (entry.value == null) {
        throw ValidationException(
          'Null value not allowed for key: ${entry.key}',
          errorDetails: {'key': entry.key},
        );
      }
    }
  }

  void _addToHistory(String action) {
    final timestamp = DateTime.now().toIso8601String();
    _history.add('[$timestamp] $action');
    if (_history.length > _maxHistorySize) {
      _history.removeAt(0);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImmutableState &&
          _data == other._data &&
          _metadata == other._metadata;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(_data.entries),
        Object.hashAll(_metadata.entries),
      );

  @override
  String toString() {
    return 'ImmutableState(data: $_data, metadata: $_metadata)';
  }
}
