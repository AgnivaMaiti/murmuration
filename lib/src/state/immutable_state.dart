class ImmutableState {
  final Map<String, dynamic> _data;

  ImmutableState() : _data = {};
  ImmutableState._internal(this._data);

  T? get<T>(String key) => _data[key] as T?;

  Map<String, dynamic> toMap() => Map.unmodifiable(_data);

  ImmutableState copyWith(Map<String, dynamic> newData) {
    return ImmutableState._internal(
      Map.from(_data)..addAll(Map.from(newData)),
    );
  }

  // ignore: unused_element
  static dynamic _deepCopy(dynamic value) {
    if (value is Map) {
      return Map.fromEntries(
        value.entries.map((e) => MapEntry(e.key, _deepCopy(e.value))),
      );
    }
    if (value is List) {
      return List.from(value.map(_deepCopy));
    }
    return value;
  }
}
